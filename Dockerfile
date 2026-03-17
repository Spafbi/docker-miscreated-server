# Dockerfile-nonroot for Miscreated Server with Wine

# Base image with Wine, Xvfb, and noVNC
FROM scottyhardy/docker-wine:latest

# ARGs for user/group IDs to be passed at build time
ARG USERNAME=steam
ARG UID=1000
ARG GID=1000

# ENV variables
ENV HOME=/home/${USERNAME}
ENV WINEPREFIX=${HOME}/.wine
ENV WINEARCH=win64
ENV PROTON_USE_NTSYNC=1
ENV WINEDLLOVERRIDES="d3d11,dxgi=n,b"
ENV DEBIAN_FRONTEND=noninteractive

# All build steps from here are run as root
# Create user and group first, so HOME directory is available
RUN groupadd -g ${GID} -o ${USERNAME} && \
    useradd -m -u ${UID} -g ${GID} -o -s /bin/bash ${USERNAME}

# Set XDG_RUNTIME_DIR for the user
ENV XDG_RUNTIME_DIR=${HOME}/runtime
RUN mkdir -p ${XDG_RUNTIME_DIR} && chmod 0700 ${XDG_RUNTIME_DIR}

# Install dependencies
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends curl sqlite3 lib32gcc-s1 && \
    rm -rf /var/lib/apt/lists/*

# Download and install steamcmd
RUN mkdir -p /opt/steamcmd && \
    curl -sSL -o /opt/steamcmd/steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -xzf /opt/steamcmd/steamcmd.tar.gz -C /opt/steamcmd && \
    rm /opt/steamcmd/steamcmd.tar.gz

# Install the Miscreated server - retrying on failure
RUN while ! /opt/steamcmd/steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir /opt/miscreated +login anonymous +app_update 302200 validate +quit; do \
        echo "SteamCMD failed with exit code $?. Retrying in 5 seconds..."; \
        sleep 5; \
    done

# Copy the entrypoint script
COPY src/entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Change ownership of all necessary files to the non-root user
RUN chown -R ${USERNAME}:${USERNAME} /opt/miscreated ${HOME} /opt/steamcmd

# Set the working directory
WORKDIR /opt/miscreated

# Switch to the non-root user for the final image
USER ${USERNAME}

# Set the entrypoint
ENTRYPOINT ["/opt/entrypoint.sh"]
