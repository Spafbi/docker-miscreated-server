FROM scottyhardy/docker-wine:latest

RUN dpkg --add-architecture i386
RUN apt update
RUN ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y --no-install-recommends tzdata
RUN dpkg-reconfigure --frontend noninteractive tzdata
RUN apt install -y wget sudo
RUN echo steam steam/question select "I AGREE" | sudo debconf-set-selections
RUN echo steam steam/license note '' | sudo debconf-set-selections
RUN apt install -y steamcmd lib32gcc-s1
RUN apt dist-upgrade -y
RUN apt upgrade -y
RUN apt autoremove -y
RUN apt install --install-recommends steamcmd -y
RUN useradd -m steam
RUN mkdir -p /opt/miscreated
RUN chown steam: /opt/miscreated
COPY src/entrypoint /usr/bin/entrypoint
RUN chown root: /usr/bin/entrypoint
RUN chmod 755 /usr/bin/entrypoint
USER steam
RUN mkdir -p /home/steam/.steam
ENV WINEDLLOVERRIDES="mscoree,mshtml="
RUN wineboot -u
RUN /usr/games/steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir /opt/miscreated +login anonymous +app_update 302200 validate +quit
WORKDIR /opt/miscreated
EXPOSE 64090-64093/udp
EXPOSE 64094/tcp
ENTRYPOINT ["/usr/bin/entrypoint"]
