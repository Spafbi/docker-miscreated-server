#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Miscreated RCON client module.

Provides a modern Python 3 interface for communicating with Miscreated servers
via their XML-RPC-based RCON protocol.  Can also be used as a standalone CLI
utility.

Usage as a module
-----------------
>>> from miscreated_server_tools.misrcon import MiscreatedRCON
>>> rcon = MiscreatedRCON(host="127.0.0.1", port=64094, password="secret")
>>> resp = rcon.send("status")
>>> print(resp.result)

Usage with auto-password from hosting.cfg
-----------------------------------------
>>> from pathlib import Path
>>> rcon = MiscreatedRCON(server_root=Path("/path/to/server"))
>>> resp = rcon.send("status")

CLI usage
---------
    python -m miscreated_server_tools.misrcon -p secret -c "status"
    python -m miscreated_server_tools.misrcon --server-root /path/to/server -c "status"
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import logging
import os
import re
import sys
import time
import xmlrpc.client
import platform
import textwrap
from dataclasses import dataclass
from os.path import basename
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


# -----------------------------------------------------------------------
# Response dataclass
# -----------------------------------------------------------------------

@dataclass
class RCONResponse:
    """Structured response returned by every RCON command."""
    success: bool
    result: Optional[str] = None
    error: Optional[str] = None

    def __bool__(self) -> bool:
        return self.success


# -----------------------------------------------------------------------
# Custom XML-RPC transport with timeout support
# -----------------------------------------------------------------------

class _RCONTransport(xmlrpc.client.Transport):
    """
    XML-RPC HTTP transport tuned for Miscreated RCON.

    Uses per-socket timeouts instead of the deprecated global
    ``socket.setdefaulttimeout()``.

    Overrides ``_parse_url`` to inject the timeout into the HTTPConnection.
    All request/send logic is delegated to the parent ``Transport`` class.
    """

    def __init__(self, timeout: float = 5.0) -> None:
        # Transport uses use_datetime=False by default which is what we want
        super().__init__()
        self._timeout = timeout

    def set_timeout(self, timeout: float) -> None:
        """Update the socket timeout used for subsequent requests."""
        self._timeout = timeout

    def _parse_url(self, host: str) -> tuple:
        """
        Return an HTTP connection for *host* with the configured timeout.

        Returns a 3-tuple ``(connection, server_name, request_path)``.
        """
        import urllib.parse

        # Split host into (servername, request_path)
        # Example host: "127.0.0.1:64094/rpc2"
        schema = "http://"
        if host.startswith(("http://", "https://")):
            schema = ""
        
        full_url = schema + host
        parsed = urllib.parse.urlparse(full_url)
        
        hostname = parsed.hostname or "127.0.0.1"
        port = parsed.port
        request_path = parsed.path or "/RPC2"
        
        # Build the server name with port
        if port is not None:
            server_name = f"{hostname}:{port}"
        else:
            server_name = hostname
            port = 80

        # Create connection with our timeout
        conn = http.client.HTTPConnection(hostname, port=port, timeout=self._timeout)
        
        return (conn, server_name, request_path)


# -----------------------------------------------------------------------
# MiscreatedRCON class
# -----------------------------------------------------------------------

class MiscreatedRCON:
    """
    Client for the Miscreated XML-RPC RCON interface.

    Parameters
    ----------
    host : str
        IP address or hostname of the game server.  Defaults to ``127.0.0.1``.
    port : int
        RCON listener port.  Defaults to ``64094`` (game port + 4).
    password : str | None
        RCON password.  If *None* and *server_root* is provided, the password
        will be read from ``hosting.cfg``.
    server_root : Path | None
        Root directory of the Miscreated game server (contains ``hosting.cfg``).
        When supplied, ``http_password`` is extracted automatically.
    retry : int
        Maximum number of authentication retries.  Defaults to ``3``.
    timeout : float
        Per-request socket timeout in seconds.  Defaults to ``5.0``.
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 64094,
        password: Optional[str] = None,
        server_root: Optional[Path] = None,
        retry: int = 3,
        timeout: float = 5.0,
    ) -> None:
        self._host = host
        self._port = port
        self._retry = retry
        self._timeout = timeout
        self._authenticated: bool = False

        # Resolve password
        if password is not None:
            self._password = password
        elif server_root is not None:
            self._password = self._load_password_from_cfg(server_root)
        else:
            raise ValueError(
                "Either 'password' or 'server_root' must be provided."
            )

        # Build XML-RPC proxy
        server_url = f"http://{host}:{port}/rpc2"
        transport = _RCONTransport(timeout=timeout)
        self._server = xmlrpc.client.ServerProxy(
            server_url, transport=transport, allow_none=True
        )
        logger.debug("RCON proxy created for %s", server_url)

    # -- password extraction --------------------------------------------

    @staticmethod
    def _load_password_from_cfg(server_root: Path) -> str:
        """
        Read ``http_password`` from *server_root*/hosting.cfg.

        Uses the existing ``cfg_parser`` module when available, falling back
        to a simple line-by-line scan.
        """
        cfg_path = server_root / "hosting.cfg"
        if not cfg_path.is_file():
            raise FileNotFoundError(
                f"hosting.cfg not found at {cfg_path}"
            )

        # Try to use the project's cfg_parser if importable
        try:
            from cfg_parser import parse_hosting_cfg  # type: ignore [import]
            lines = parse_hosting_cfg(cfg_path)
            for line in lines:
                if line.cvar_name == "http_password" and line.is_active:
                    return line.value  # type: ignore [return-value]
        except ImportError:
            pass

        # Fallback: simple scan
        with open(cfg_path, "r", encoding="utf-8") as fh:
            for raw in fh:
                stripped = raw.strip()
                # Skip commented lines
                if stripped.startswith("-- "):
                    continue
                if "=" in stripped:
                    name, _, value = stripped.partition("=")
                    if name.strip() == "http_password":
                        # Strip trailing comment
                        value = value.split(" - ")[0].strip()
                        # Remove surrounding quotes if present
                        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                            value = value[1:-1]
                        return value

        raise ValueError(
            f"'http_password' not found (or is commented out) in {cfg_path}"
        )

    # -- authentication -------------------------------------------------

    def authenticate(self) -> bool:
        """
        Perform the challenge-authenticate handshake.

        Returns ``True`` on success, ``False`` after all retries exhausted.
        """
        if self._authenticated:
            logger.debug("Already authenticated; skipping.")
            return True

        for attempt in range(1, self._retry + 1):
            try:
                challenge = self._server.challenge()
                challenge_str = str(challenge).strip()

                auth_string = f"{challenge_str}:{self._password}"
                md5_hash = hashlib.md5(
                    auth_string.encode("utf-8")
                ).hexdigest()

                result = self._server.authenticate(md5_hash)

                if result == "authorized":
                    self._authenticated = True
                    logger.info("RCON authenticated (attempt %d)", attempt)
                    return True

                logger.warning(
                    "RCON authenticate returned %r (attempt %d)", result, attempt
                )

            except (OSError, http.client.BadStatusLine, xmlrpc.client.Fault) as exc:
                logger.debug(
                    "RCON challenge/auth error (attempt %d): %s", attempt, exc
                )

            # Exponential back-off before retry
            if attempt < self._retry:
                backoff = 0.25 * (2 ** (attempt - 1))
                time.sleep(backoff)

        logger.error("RCON authentication failed after %d attempts", self._retry)
        return False

    # -- command execution ----------------------------------------------

    def _execute(self, cmd: str, params: str = "") -> RCONResponse:
        """
        Internal helper: execute a single RPC call.

        *params* is passed as a single positional argument when non-empty.
        """
        try:
            rpc_method = self._server.__getattr__(cmd)
            if params:
                raw = rpc_method(params)
            else:
                raw = rpc_method()

            result = str(raw).strip() if raw is not None else ""
            return RCONResponse(success=True, result=result)

        except xmlrpc.client.Fault as exc:
            return RCONResponse(success=False, error=f"XML-RPC fault: {exc}")
        except (OSError, http.client.BadStatusLine, ConnectionRefusedError) as exc:
            return RCONResponse(success=False, error=f"Connection error: {exc}")

    def _split_say_command(self, command: str) -> List[str]:
        """
        Split an sv_say command into multiple commands if the message exceeds 48 characters.
        
        For sv_say commands, splits the message at word boundaries to ensure no word is broken.
        Empty messages are filtered out.
        
        Parameters
        ----------
        command : str
            The full command string (e.g., "sv_say Hello world...")
            
        Returns
        -------
        List[str]
            List of command strings to send (single command if under 48 chars, 
            multiple commands if split)
        """
        # Check if this is an sv_say command (case-insensitive)
        command_lower = command.strip().lower()
        if not command_lower.startswith("sv_say"):
            # Not an sv_say command, return as-is
            return [command]
        
        # Extract the message part (everything after "sv_say")
        message = command[len("sv_say"):].strip()
        
        # If message is empty, don't send anything
        if not message:
            return []
        
        # Check if message is already under 48 characters
        if len(message) <= 48:
            # No splitting needed
            return [command]
        
        # Split message at word boundaries (break_long_words=False prevents splitting words)
        lines = textwrap.wrap(message, 48, break_on_hyphens=True, break_long_words=False)
        
        # Create sv_say commands for each line with ASCII encoding
        commands = []
        for line in lines:
            # Encode to ASCII with error handling to avoid non-ASCII characters
            encoded_line = line.encode("ascii", errors="ignore").decode()
            # Only add command if the line is not empty after encoding
            if encoded_line.strip():
                cmd = f"sv_say {encoded_line}"
                commands.append(cmd)
        
        return commands

    def send(self, command: str) -> RCONResponse:
        """
        Send a single RCON command.

        The command string is split on the first space: the first token is the
        RCON command name, the remainder is passed as a single parameter.

        If the command is an sv_say command and the message exceeds 48 characters,
        it will be automatically split into multiple sv_say commands.

        Parameters
        ----------
        command : str
        """
        if not command:
            return RCONResponse(success=False, error="Empty command")

        # Check if this is an sv_say command and needs splitting
        split_commands = self._split_say_command(command)
        
        # If we have multiple commands (split), send them sequentially
        if len(split_commands) > 1:
            results = []
            for cmd in split_commands:
                # For each split command, call send recursively to maintain authentication
                resp = self.send(cmd)
                results.append(resp)
            
            # Combine results - if any failed, overall is a failure
            success = all(r.success for r in results)
            if success:
                # Concatenate all results
                result = "\n".join(r.result for r in results if r.result)
                return RCONResponse(success=True, result=result)
            else:
                # Return the first error
                error = next((r.error for r in results if r.error), "Unknown error")
                return RCONResponse(success=False, error=error)
        
        # Single command case (no splitting needed)
        parts = command.split(" ", 1)
        cmd = parts[0]
        params = parts[1] if len(parts) > 1 else ""

        # Fast path: try without re-authenticating
        resp = self._execute(cmd, params)

        # If we got an "unauthorized"-style error, re-auth and retry
        if resp.success:
            # Check for known error responses that indicate unauthorised access
            if not self._is_error_response(resp.result):
                return resp

        # Re-authenticate and retry once
        if self.authenticate():
            resp = self._execute(cmd, params)

        if not resp.success:
            resp.error = f"Command '{command}' failed: {resp.error}"
        return resp

    def send_many(self, commands: List[str]) -> Dict[str, RCONResponse]:
        """
        Send multiple RCON commands in sequence.

        Returns a dictionary mapping each command string to its ``RCONResponse``.
        """
        # Ensure authenticated before batching
        self.authenticate()

        results: Dict[str, RCONResponse] = {}
        for cmd_str in commands:
            results[cmd_str] = self.send(cmd_str)
        return results

    # -- helpers --------------------------------------------------------

    @staticmethod
    def _is_error_response(result: Optional[str]) -> bool:
        """Return ``True`` when *result* looks like an error rather than data."""
        if result is None:
            return False
        sentinel = result[:11]
        if sentinel == "Illegal Com":
            return True
        if result.startswith("[Whitelist]"):
            return True
        return False

    def close(self) -> None:
        """Release resources.  Idempotent."""
        self._authenticated = False
        # ServerProxy doesn't have a real close but signal intent
        self._server = None  # type: ignore [assignment]


# -----------------------------------------------------------------------
# CLI entry-point
# -----------------------------------------------------------------------

# Color code mapping: CryEngine $N -> ANSI color
COLOR_MAP = {
    "0": "\033[0m",      # Reset/Default
    "1": "\033[31m",     # Red
    "2": "\033[32m",     # Green
    "3": "\033[33m",     # Yellow
    "4": "\033[34m",     # Blue
    "5": "\033[36m",     # Cyan
    "6": "\033[37m",     # White
    "7": "\033[35m",     # Magenta
}

def _enable_windows_ansi():
    """Enable ANSI escape code support on Windows CMD."""
    if platform.system() == "Windows":
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
            kernel32.SetConsoleMode(handle, 7)   # ENABLE_PROCESSED_OUTPUT | ENABLE_WRAP_AT_EOL_OUTPUT
            # Enable VT processing (flag 4)
            mode = ctypes.c_ulong()
            kernel32.GetConsoleMode(handle, ctypes.byref(mode))
            kernel32.SetConsoleMode(handle, mode.value | 4)
        except (AttributeError, OSError):
            pass  # Fallback: ANSI may already be enabled on Win10+

def _apply_color_codes(text: str) -> str:
    """Convert CryEngine $N color codes to ANSI escape sequences."""
    def replace_color(match):
        code = match.group(1)
        return COLOR_MAP.get(code, match.group(0))
    
    # Pattern matches $ followed by a single digit
    return re.sub(r'\$([0-7])', replace_color, text)

def _strip_color_codes(text: str) -> str:
    """Remove all CryEngine $N color codes."""
    return re.sub(r'\$[0-7]', '', text)

def _build_cli_parser() -> Any:
    prog = basename(__file__) if "__file__" in globals() else "misrcon"
    parser = argparse.ArgumentParser(
        prog=prog,
        description=(
            "Miscreated RCON client.  Sends commands to a Miscreated "
            "game server via XML-RPC."
        ),
    )
    parser.add_argument(
        "-s", "--server",
        default="127.0.0.1",
        help="Server IP or hostname (default: 127.0.0.1)",
    )
    parser.add_argument(
        "-r", "--rcon-port",
        type=int,
        default=None,
        help="RCON port (default: None, will use BASE_PORT env var if set)",
    )
    parser.add_argument(
        "-g", "--game-port",
        type=int,
        default=64090,
        help=(
            "Game port.  If different from default, RCON port will be "
            "calculated as game-port + 4."
        ),
    )
    parser.add_argument(
        "-p", "--password",
        help="RCON password (required if --server-root not given)",
    )
    parser.add_argument(
        "-d", "--server-root",
        help=(
            "Path to the Miscreated server root directory containing "
            "hosting.cfg.  Password is read automatically."
        ),
    )
    parser.add_argument(
        "-c", "--command",
        default="status",
        help='RCON command to execute (default: "status")',
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable debug logging",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable color output",
    )
    parser.add_argument(
        "--color",
        choices=["auto", "always", "never"],
        default="auto",
        help="Enable color output (default: auto)",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry-point.  Returns 0 on success, 1 on failure."""
    parser = _build_cli_parser()
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    # Calculate RCON port from game port when non-default
    if args.game_port != 64090:
        rcon_port = args.game_port + 4
    elif args.rcon_port is not None:
        # User explicitly passed --rcon-port
        rcon_port = args.rcon_port
    else:
        # Check BASE_PORT environment variable and add 4 (as requested in task)
        base_port_str = os.environ.get("BASE_PORT")
        if base_port_str is not None:
            try:
                base_port = int(base_port_str)
                rcon_port = base_port + 4
            except ValueError:
                logger.warning("BASE_PORT environment variable is not a valid integer, using default 64094")
                rcon_port = 64094
        else:
            # Use default RCON port
            rcon_port = 64094

    # Validate password / server-root
    if args.password is None and args.server_root is None:
        # Check if /server/hosting.cfg exists for auto-detection
        default_cfg_path = Path("/server/hosting.cfg")
        if default_cfg_path.is_file():
            args.server_root = "/server"
            logger.info("Auto-detected server root at /server from hosting.cfg")
        else:
            logger.error("Either -p/--password or -d/--server-root is required.")
            return 1

    try:
        server_root = Path(args.server_root) if args.server_root else None
        rcon = MiscreatedRCON(
            host=args.server,
            port=rcon_port,
            password=args.password,
            server_root=server_root,
        )
    except (ValueError, FileNotFoundError) as exc:
        logger.error("Initialization error: %s", exc)
        return 1

    resp = rcon.send(args.command)

    if resp.success:
        output = resp.result if resp.result else "<empty result - ok>"
        
        # Handle color output
        use_color = False
        
        # Check if colors should be enabled
        if args.no_color:
            use_color = Falses
        elif args.color == "always":
            use_color = True
        elif args.color == "never":
            use_color = False
        else:  # args.color == "auto"
            # Auto mode: enable colors if stdout is a TTY and NO_COLOR is not set
            use_color = (
                sys.stdout.isatty() and 
                not os.environ.get("NO_COLOR")
            )
        
        if use_color:
            _enable_windows_ansi()
            output = _apply_color_codes(output)
            output += "\033[0m"  # Reset to default color at the end
        else:
            output = _strip_color_codes(output)
            
        print(output)
        rcon.close()
        return 0
    else:
        logger.error("Command failed: %s", resp.error)
        rcon.close()
        return 1


if __name__ == "__main__":
    sys.exit(main())