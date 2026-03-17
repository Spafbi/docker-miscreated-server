# Miscreated Docker Wine Server

This project provides a way to run a Miscreated dedicated server using Docker and Wine. It includes a `Dockerfile` to build the server image and a `docker-compose.yml` file to easily manage the server container. The server is configured through a `.env` file and a `hosting.cfg` file. A setup script is provided to help with the initial configuration.

## Files

-   **`.env-example`**: An example file for the environment variables used by `docker-compose.yml` and the `setup.sh` script. You should copy this to `.env` and modify it.
-   **`docker-compose.yml`**: The Docker Compose file to define and run the Miscreated server container. It uses environment variables from the `.env` file to configure the server.
-   **`Dockerfile`**: The Dockerfile to build the Miscreated server image. It uses a base image with Wine, installs the Miscreated server using `steamcmd`, and sets up the container environment.
-   **`entrypoint.sh`**: The entrypoint script for the Docker container. It constructs the server's command-line arguments from environment variables and starts the Miscreated server.
-   **`hosting.cfg.example`**: An example configuration file for the Miscreated server. This file is copied to `hosting.cfg` during the setup process and can be modified to customize server settings.
-   **`setup.sh`**: A script to interactively configure the Miscreated server. It generates the `.env` file, creates the `hosting.cfg` file, and builds the Docker image if it doesn't exist.

## Environment Variables

The following environment variables can be set in the `.env` file to configure the server. This file is created by the `setup.sh` script.

-   `BASE_PORT`: The base port for the server. The server will use a range of ports starting from this one. Defaults to `64090`.
-   `GRANT_ALL_GUIDES`: If set to `1`, this will grant all crafting guides to all players. Defaults to `0`.
-   `IMAGE`: The name for the Docker image. Defaults to `miscreated`.
-   `IMAGE_TAG`: The tag for the Docker image. Defaults to `latest`.
-   `MAP`: The map to load for the server. Defaults to `islands`.
-   `MAX_PLAYERS`: The maximum number of players that can connect to the server. Defaults to `36`.
-   `MIS_GAMESERVERID`: A unique ID for your server. Defaults to `100`. This value should be retained unless using a database from a previous server installation which used a different ID.
-   `SAVE_DIR`: The directory where the server's persistent files will be stored. Defaults to the current directory (`.`).
-   `WHITELISTED`: If set to `1`, only players on the whitelist will be able to connect. Defaults to `0`.

## How to Use

### 1. Setup

Run the setup script to configure your server. This will prompt you for various settings and create the necessary configuration files.

```bash
bash ./setup.sh
```

The script will guide you through creating a `.env` file and a `hosting.cfg` file. After the setup, you can further customize your server by editing the `hosting.cfg` file.

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

## Server Data and Mods

### Persistent Data
By default, the server's persistent files (database, logs, configuration) are stored in the same directory as the project files. This is controlled by the `SAVE_DIR` variable in your `.env` file, which defaults to the current directory (`.`).

### Multiple Servers
If you plan to run multiple Miscreated servers, each server instance must have its own separate copy of this project's files to avoid conflicts with port numbers and persistent data.

### Mods
Some server mods may require additional files or create their own persistent data. To support this, you may need to edit the `docker-compose.yml` file to mount additional files or directories into the container. You can add more volume mounts under the `services.miscreated.volumes` section. For example:

```yaml
volumes:
  - ${SAVE_DIR:-.}/banned.xml:/opt/miscreated/banned.xml
  # ... other volumes
  - ./path/to/your/modfile.txt:/opt/miscreated/modfile.txt
```
