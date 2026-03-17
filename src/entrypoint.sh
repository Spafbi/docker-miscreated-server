#!/bin/bash
BASE_PORT=${BASE_PORT:-64090}
GRANT_ALL_GUIDES=${GRANT_ALL_GUIDES:-0}
MAP=${MAP:-islands}
MIS_GAMESERVERID=${MIS_GAMESERVERID:-100}
MAX_PLAYERS=${MAX_PLAYERS:-36}
WHITELISTED=${WHITELISTED:-0}

# Construct the command line arguments
ARGS=""

# Add sv_port from UDP_RANGE
ARGS="$ARGS -sv_port $BASE_PORT"

# Add map
ARGS="$ARGS +map $MAP"

# Add max players, with validation
if [[ "$MAX_PLAYERS" =~ ^[0-9]+$ ]] && [ "$MAX_PLAYERS" -ge 1 ] && [ "$MAX_PLAYERS" -le 100 ]; then
    ARGS="$ARGS +sv_maxplayers $MAX_PLAYERS"
else
    echo "MAX_PLAYERS must be a number between 1 and 100. Using default of 36."
    ARGS="$ARGS +sv_maxplayers 36"
fi

# Add server ID, with validation
if [[ "$MIS_GAMESERVERID" =~ ^[0-9]+$ ]]; then
    ARGS="$ARGS -mis_gameserverid $MIS_GAMESERVERID"
else
    echo "MIS_GAMESERVERID must be a numeric value. Using default of 100."
    ARGS="$ARGS -mis_gameserverid 100"
fi

# Add whitelist if enabled
WHITELISTED_LOWER=$(echo "$WHITELISTED" | tr '[:upper:]' '[:lower:]')
if [ "$WHITELISTED_LOWER" = "1" ] || [ "$WHITELISTED_LOWER" = "y" ] || [ "$WHITELISTED_LOWER" = "yes" ] || [ "$WHITELISTED_LOWER" = "true" ]; then
    ARGS="$ARGS -mis_whitelist"
fi

# Grant all guides if enabled
GRANT_ALL_GUIDES_LOWER=$(echo "$GRANT_ALL_GUIDES" | tr '[:upper:]' '[:lower:]')
if [ "$GRANT_ALL_GUIDES_LOWER" = "1" ] || [ "$GRANT_ALL_GUIDES_LOWER" = "y" ] || [ "$GRANT_ALL_GUIDES_LOWER" = "yes" ] || [ "$GRANT_ALL_GUIDES_LOWER" = "true" ]; then
    echo "GRANT_ALL_GUIDES is enabled. Applying SQL changes."
    sqlite3 miscreated.db <<EOF
DROP TRIGGER IF EXISTS grant_all_guides;
CREATE TRIGGER IF NOT EXISTS grant_all_guides
   AFTER UPDATE
   ON Characters
BEGIN
 UPDATE ServerAccountData SET Guide00="-1", Guide01="-1";
END;
UPDATE ServerAccountData SET Guide00="-1", Guide01="-1";
EOF
fi

# Add http start server
ARGS="$ARGS +http_startserver"

# Start the Miscreated server with Wine
echo "Starting Miscreated Server with command: MiscreatedServer.exe $ARGS"
xvfb-run --auto-servernum sh -c "wine /opt/miscreated/Bin64_dedicated/MiscreatedServer.exe $ARGS"