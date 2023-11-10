#!/bin/bash
## You can override some vars here ##

#BASEPORT=64090
#CONTAINER_NAME=miscreated_server
#DOCKER_IMAGE=shdw_miscreated
#DOCKER_RESTART=always
#IP_ADDRESS=0.0.0.0

## End var overrides ##

# DO NOT EDIT BELOW THIS LINE!!!
scriptDir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
dockerRunDir="/opt/miscreated"

function loadEnv() {
  while IFS= read -r line; do if [[ -n $line ]]; then export "$line"; fi; done < "${runDir}/env"
}

function mapObjects() {
  DOCKER_BINDS=""
  for o in ${runDir}/*; do
    DOCKER_BINDS="${DOCKER_BINDS} -v ${o}:${dockerRunDir}/$(basename ${o})"
  done
}

while getopts ":c:i:p:" o; do
    case "${o}" in
        c)
            CONTAINER_NAME=${OPTARG}
            ;;
        i)
            IP_ADDRESS=${OPTARG}
            ;;
        p)
            BASEPORT=${OPTARG}
            ;;
        *)
            ;;
    esac
done

CONTAINER_NAME=${CONTAINER_NAME:=miscreated_server}
IP_ADDRESS=${IP_ADDRESS:=0.0.0.0}
GAME_PORT=${BASEPORT:=64090}
GAME_PORTS=${GAME_PORT}-$((${GAME_PORT} + 3))
RCON_PORT=$((${GAME_PORT} + 4))
DOCKER_RESTART=${DOCKER_RESTART:=always}
DOCKER_IMAGE=${DOCKER_IMAGE:=shdw_miscreated}

runDir="${scriptDir}/${CONTAINER_NAME//[^[:alnum:]]/}"

mkdir -p "${runDir}"

default_bind_dirs=( "DatabaseBackups" "logbackups" "logs" )
for d in ${default_bind_dirs[@]}; do
  mkdir -p "${runDir}/${d}"
  chmod 777 "${runDir}/${d}"
done

default_bind_files=( "blacklist.xml" "miscreated.db" "reservations.xml" "whitelist.xml")
for f in ${default_bind_files[@]}; do
  touch "${runDir}/${f}"
  chmod 666 "${runDir}/${f}"
done

cp "${scriptDir}/src/run-miscreated-server.sh" "${runDir}/run-miscreated-server.sh"

find ${runDir}/ -type f -exec chmod 666 {} \;
find ${runDir}/ -type d -exec chmod 1777 {} \;

if [ ! -f ${runDir}/hosting.cfg ]; then
  FIRST_RUN=1 # This var will be used at a later time
  cat > ${runDir}/hosting.cfg <<'endOfHostingCfg'
- Remove '- ' from the following line to enable 500 build parts and seasonal events mods
- steam_ugc=2075026891,2632671232

http_password=HASHPASSWORD
sv_maxuptime=12
sv_servername="Docker Miscreated Server UNIXEPOCH"
g_playerWeightLimit=60

- sv_motd="Put a message to players here. Shown on join. Remove '- ' from the start of this line to enable"
- sv_url="Put a message to players here. Shown on join. Remove '- ' from the start of this line to enable"
endOfHostingCfg
  sed -i "s/UNIXEPOCH/$(date +%s)/g" ${runDir}/hosting.cfg
  THIS_HASH=$(date +%s|md5sum)
  sed -i "s/HASHPASSWORD/${THIS_HASH:0:8}/g" ${runDir}/hosting.cfg
  chmod 666 ${runDir}/hosting.cfg
  cat ${runDir}/hosting.cfg
else
  FIRST_RUN=0
fi

if [ ! -f ${runDir}/env ]; then
  cat > ${runDir}/env <<'endOfEnv'
MAP_NAME=islands
MAX_PLAYERS=36
SERVER_ID=100
RUN_SERVER=1
WHITELISTED=0
endOfEnv
  chmod 644 ${runDir}/env
fi

loadEnv
mapObjects

docker stop ${CONTAINER_NAME} 2>/dev/null
docker rm ${CONTAINER_NAME} 2>/dev/null
chmod 755 "${runDir}/run-miscreated-server.sh"
eval "docker run -d --restart=${DOCKER_RESTART} -p ${IP_ADDRESS}:${GAME_PORTS}:64090-64093/udp -p ${IP_ADDRESS}:${RCON_PORT}:64094/tcp --name=${CONTAINER_NAME} ${DOCKER_BINDS} ${DOCKER_IMAGE} ${dockerRunDir}/run-miscreated-server.sh"
