# Miscreated Docker Wine Server

This project provides a way to run a Miscreated dedicated server using Docker and Wine. It includes a `Dockerfile` to build the server image and a `docker-compose.yml` file to easily manage the server container. The server is configured through a `.env` file and a `hosting.cfg` file.

## Files

-   **`.env-example`**: An example file for the environment variables used by `docker-compose.yml`. You should copy this to `.env` and modify it.
-   **`docker-compose.yml`**: The Docker Compose file to define and run the Miscreated server container. It uses environment variables from the `.env` file to configure the server.
-   **`Dockerfile`**: The Dockerfile to build the Miscreated server image. It uses a base image with Wine, installs the Miscreated server using `steamcmd`, and sets up the container environment.
-   **`src/entrypoint.sh`**: The entrypoint script for the Docker container. It constructs the server's command-line arguments from environment variables and starts the Miscreated server.
-   **`src/misrcon.py`**: Python script used by the healthcheck to monitor the server via RCON.
-   **`src/rcon`**: Binary used by `misrcon.py` for RCON communication.
-   **`hosting.cfg.example`**: An example configuration file for the Miscreated server. This file is copied to `hosting.cfg` during the setup process and can be modified to customize server settings.
-   **`.gitignore`**: Lists files and directories that are excluded from version control, including server data.

## Environment Variables

The following environment variables can be set in the `.env` file to configure the server. This file is created by copying `.env-example`.

-   `BASE_PORT`: The base port for the server. The server will use a range of ports starting from this one. Defaults to `64090`.
-   `GRANT_ALL_GUIDES`: If set to `1`, this will grant all crafting guides to all players. Defaults to `0`.
-   `MAP`: The map to load for the server. Defaults to `islands`.
-   `MAX_PLAYERS`: The maximum number of players that can connect to the server. Must be a number between 1 and 100. Defaults to `36`.
-   `MIS_GAMESERVERID`: A unique ID for your server. Defaults to `100`. This value should be retained unless using a database from a previous server installation which used a different ID.
-   `WHITELISTED`: If set to `1`, only players on the whitelist will be able to connect. Defaults to `0`.
-   `BASE_VEHICLE_LIMITER`: Limits vehicles per PlotSign (excluding bicycles, tractors, quadbikes, and jetskis). Set to `-1` to disable. Defaults to `-1`.
-   `STEAM_AUTH_TOKEN`: Optional Steam authentication token. Most users will not need this. Defaults to empty.
-   `VARIABLE_RESTARTS`: If set to `1`, enables random server restarts between 8 and 12 hours. Defaults to `1`.

## How to Use

### Setup

Copy the `.env-example` file to `.env` and modify it as needed:

```bash
cp .env-example .env
```

Edit the `.env` file with your preferred settings, and optionally edit the `hosting.cfg.example` file before copying it to `hosting.cfg`.

### 2. Manage the Server

-   **Start the Server**: To start the Miscreated server in detached mode, run:
    ```bash
    docker compose up -d
    ```

-   **Restart the Server**: To restart the server:
    ```bash
    docker compose restart
    ```

-   **Stop the Server**: To stop the server and remove the container:
    ```bash
    docker compose down
    ```

## Docker Compose Configuration

The `docker-compose.yml` file configures the server with:

- **Resource Limits**: 
  - Memory: 6G (should be increased to at least 8G for servers with more than 50 max players)
  - CPU: 2.5 cores
  - PID limit: 256

- **Security Features**:
  - Runs as non-root user
  - No new privileges (`no-new-privileges:true`)
  - Capabilities dropped (`ALL`) and added (`NET_BIND_SERVICE`)
  - Network isolation via `mis-network` bridge network

- **Healthcheck**: Uses Python script (`misrcon.py`) to monitor server status

- **Temporary File System (tmpfs)**:
  - `/tmp:size=512M,noexec,nosuid`
  - `/run:size=10M,noexec,nosuid`

- **Logging**: Rotates logs with max size of 50MB and 5 files retained

## Special Features

### Vehicle Limiter
When `BASE_VEHICLE_LIMITER` is set to a positive number, the server will limit vehicles near PlotSigns. This prevents excessive vehicle accumulation in areas.

### Grant All Guides
When `GRANT_ALL_GUIDES` is enabled, the server will unlock all crafting guides for new players by modifying the SQLite database.

### Variable Restarts
When `VARIABLE_RESTARTS` is enabled, servers will restart at random intervals between 8 and 12 hours to prevent coordinated griefing.
