# Dockerfile-nonroot for Miscreated Server with Wine

# Ubuntu base: Wine, Xvfb, and all headless server dependencies are installed
# natively below (no RDP / VNC / noVNC components)
FROM ubuntu:resolute

# ARGs for user/group IDs to be passed at build time
ARG UID=1000
ARG GID=1000

# ENV variables
ENV USERNAME=steam
ENV HOME=/home/${USERNAME}
ENV WINEPREFIX=${HOME}/.wine
ENV WINEARCH=win64
ENV PROTON_USE_NTSYNC=1
ENV WINEDLLOVERRIDES="d3d11,dxgi=n,b"
ENV WINEDEBUG=-all
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# All build steps from here are run as root
# Set XDG_RUNTIME_DIR for the user
ENV XDG_RUNTIME_DIR=${HOME}/runtime
RUN mkdir -p ${XDG_RUNTIME_DIR} && chmod 0700 ${XDG_RUNTIME_DIR}

# Install headless Wine, the Xvfb virtual display, and server tooling
# (i386 arch enables the 32-bit Wine loader). Note: on Ubuntu 26.04 the
# dos2unix package ships both the dos2unix and unix2dos binaries (there
# is no separate unix2dos package).
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dos2unix \
        locales \
        python3 \
        sqlite3 \
        tzdata \
        xvfb \
        xauth \
        x11-utils \
        wine \
        wine64 \
        wine32 \
        lib32gcc-s1 && \
    rm -rf /var/lib/apt/lists/*

# Enable the en_US.UTF-8 locale (Wine requires a generated UTF-8 locale)
RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen

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

# Create the non-root user and group. Done after the heavy install steps
# (Wine, steamcmd) so that changing UID/GID only rebuilds these final layers
# instead of invalidating those cached installs. The -o flags allow
# non-unique IDs if your environment requires them.
RUN set -e; \
    case "${UID}" in '' | *[!0-9]*) echo "ERROR: UID must be a non-negative integer (got '${UID}')" >&2; exit 1;; esac; \
    case "${GID}" in '' | *[!0-9]*) echo "ERROR: GID must be a non-negative integer (got '${GID}')" >&2; exit 1;; esac; \
    if [ "${UID}" -lt 100 ]; then echo "ERROR: UID must be >= 100 (got ${UID})" >&2; exit 1; fi; \
    if [ "${GID}" -lt 100 ]; then echo "ERROR: GID must be >= 100 (got ${GID})" >&2; exit 1; fi; \
    groupadd -g ${GID} -o ${USERNAME} && \
    useradd -m -u ${UID} -g ${GID} -o -s /bin/bash ${USERNAME}

# Create /server, and change ownership of all necessary files and directories to the non-root user
RUN mkdir /server && \
    chown -R ${USERNAME}:${USERNAME} /server ${HOME} /opt/steamcmd

# Set the working directory
WORKDIR /server

# Switch to the non-root user for the final image
USER ${USERNAME}

# Healthcheck: query the server via RCON (misrcon.py defaults to the "status" command)
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=300s \
    CMD python3 /usr/local/bin/misrcon.py || exit 1

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
