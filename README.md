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

-   **Force Rebuild the Image**: If you need to rebuild the Docker image after changing the `Dockerfile`, the base image, or any build-time assets, use one of these commands:
    ```bash
    docker compose up -d --build
    ```
    or
    ```bash
    docker compose build --no-cache
    docker compose up -d
    ```

Why rebuild? A rebuild might be warranted in the following scenarios:
-   You've modified the `Dockerfile` and want to apply your changes.
-   The base image (e.g., Wine or Ubuntu version) has been updated upstream, and you want to pull the latest version.
-   You've updated files that are copied into the image at build time (like `entrypoint.sh`).
-   You're troubleshooting unexpected behavior that might be caused by stale build cache layers.
-   You've updated `docker-compose.yml` with new build arguments and want to ensure they take effect.

Option 1 (`--build`): This option rebuilds only the layers that have changed, using Docker's build cache. It's faster and suitable for most daily updates.
Option 2 (`--no-cache`): This option ignores all cached layers and rebuilds every layer from scratch. While slower, it guarantees a completely fresh image and is useful when troubleshooting or after major base-image updates.

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

### RCON (Remote Console)
The Miscreated server includes built-in RCON functionality accessible via a wrapper script. You can execute RCON commands using `docker exec -it <container_name> rcon <command>`.

For example:
```bash
# Check server status
docker exec -it miscreated rcon status

# Send a message to all players
docker exec -it miscreated rcon sv_say Welcome to the server!
```

For advanced usage or custom configurations, you can use `misrcon.py` directly:
```bash
# Run misrcon.py directly with custom parameters
docker exec -it miscreated python3 misrcon.py --server-root /server -c "status"
```

### Updating Service Name and Container Name
The default service name is `mis1` and the container name is `miscreated_wine_test`. You can change these to something more meaningful for your setup:

1. **Service Name**: Change `mis1` in the `docker-compose.yml` file to a descriptive name like `mis-created-survival` or `zombieland`
2. **Container Name**: Update `container_name: miscreated_wine_test` to match your service name or something else meaningful

Both names should be consistent with the examples used throughout the documentation, especially for RCON commands.

### Running Multiple Servers
To run multiple Miscreated servers, you can copy the `mis1` section in `docker-compose.yml` for each server you want to run:

```yaml
  mis2:
    <<: *mis-common
    container_name: my-other-miscreated-server
    ports:
      - "64194:64194"
      - "64190-64193:64190-64193/udp"
    environment:
      - BASE_PORT=64190
      - GRANT_ALL_GUIDES=1
      - MAP=islands
      - MAX_PLAYERS=50
      - MIS_GAMESERVERID=100
      - WHITELISTED=0
      - BASE_VEHICLE_LIMITER=1
      - STEAM_AUTH_TOKEN=${GSLT2}
      - VARIABLE_RESTARTS=1
    volumes:
      - ./data2:/server
```

When copying the service section, ensure you:
1. Change the **service name** (`mis1` → `mis2`)
2. Update the **container_name**
3. Change **all port mappings** (both external and internal) to avoid conflicts:
   - TCP port: `"64094:64094"` → `"64194:64194"`
   - UDP range: `"64090-64093:64090-64093/udp"` → `"64190-64193:64190-64193/udp"`
4. Update **BASE_PORT** to match your new port range
5. Change the **volume mount** from `./data:/server` to `./data2:/server`
6. Use a different **GSLT token** if needed (e.g., `${GSLT2}` instead of `${GSLT1}`)