# Dockerfile-nonroot for Miscreated Server with Wine

# Base image with Wine, Xvfb, and noVNC
# Pinned to the stable 11.0 line for reproducible builds (currently the same
# image as :latest). For fully reproducible builds use a dated tag, e.g.
# scottyhardy/docker-wine:stable-11.0-20260816
FROM scottyhardy/docker-wine:stable-11.0

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
    apt-get install -y --no-install-recommends curl python3 sqlite3 lib32gcc-s1 && \
    rm -rf /var/lib/apt/lists/*

# Download and install steamcmd
RUN mkdir -p /opt/steamcmd && \
    curl -sSL -o /opt/steamcmd/steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -xzf /opt/steamcmd/steamcmd.tar.gz -C /opt/steamcmd && \
    rm /opt/steamcmd/steamcmd.tar.gz

# Copy the entrypoint script
COPY src/entrypoint.sh /entrypoint.sh
COPY src/misrcon.py /usr/local/bin/misrcon.py
COPY src/rcon /usr/local/bin/rcon
RUN chmod +x /entrypoint.sh /usr/local/bin/misrcon.py /usr/local/bin/rcon

# Create /server, and change ownership of all necessary files and directories to the non-root user
RUN mkdir /server && \
    chown -R ${USERNAME}:${USERNAME} /server ${HOME} /opt/steamcmd

# Set the working directory
WORKDIR /server

# Switch to the non-root user for the final image
USER ${USERNAME}

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
