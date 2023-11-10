#!/bin/bash
function loadEnv() {
  while IFS= read -r line; do if [[ -n $line ]]; then export "$line"; fi; done < "/opt/miscreated/env"
}

loadEnv
if [ -d "/opt/miscreated/mods" ]; then
  echo "Clearing mods directory to ensure all mods are current..."
  rm -rf "/opt/miscreated/mods"
fi

SERVER_ID=${SERVER_ID:=100}
MAX_PLAYERS=${MAX_PLAYERS:=36}
MAP_NAME=${MAP_NAME:=islands}

[ "$WHITELISTED" -eq 1 ] && WHITELIST_STRING="-mis_whitelist" || WHITELIST_STRING=""

while true; do

# This is here to cause the Miscreated server proces to wait to start to give
# an admin time to gracefully shutdown the Docker container by setting the 
# RUN_SERVER value in run/env to 0 and shutting down or restarting the server.
if [[ "${RUN_SERVER:=1}" == "0" ]]; then sleep 99999999; fi

xvfb-run wine /opt/miscreated/Bin64_dedicated/MiscreatedServer.exe -mis_gameserverid ${SERVER_ID} +sv_maxplayers ${MAX_PLAYERS} +map ${MAP_NAME} +http_startserver ${WHITELIST_STRING}

done
