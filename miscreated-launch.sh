#!/bin/sh

# Execute scripts prior to server startup
for f in /usr/games/Steam/steamapps/common/MiscreatedServer/DockerScripts/*.sh; do
  bash "$f" 
done

# Start services
service game-server start

if [ "$RDP_SERVER" = "yes" ]; then
  service xrdp start
fi

# Keep-alive
sleep infinity
