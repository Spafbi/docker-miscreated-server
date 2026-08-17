#!/bin/bash
BASE_PORT=${BASE_PORT:-64090}
BASE_VEHICLE_LIMITER=${BASE_VEHICLE_LIMITER:--1}
DB_PATH="/server/miscreated.db"
GRANT_ALL_GUIDES=${GRANT_ALL_GUIDES:-0}
MAP=${MAP:-islands}
MAX_PLAYERS=${MAX_PLAYERS:-36}
MIS_GAMESERVERID=${MIS_GAMESERVERID:-100}
STEAM_AUTH_TOKEN=${STEAM_AUTH_TOKEN:-}
VARIABLE_RESTARTS=${VARIABLE_RESTARTS:-1}
WHITELISTED=${WHITELISTED:-0}

# RCON (and therefore the container healthcheck) requires the server's
# hosting.cfg to be present.  It is provisioned manually from the host.
if [ ! -f /server/hosting.cfg ]; then
    echo "WARNING: /server/hosting.cfg not found. RCON and the healthcheck require it."
    echo "WARNING: Copy hosting.cfg.example to data/hosting.cfg on the host (container path /server/hosting.cfg)."
fi

# Helper function to check database validity and required tables
_db_check_passed() {
    local required_tables=("$@")
    
    # Check if database file exists
    if [ ! -f "$DB_PATH" ]; then
        echo "WARNING: $DB_PATH not found. Skipping changes."
        return 1
    fi
    
    # Validate SQLite3 database
    if ! sqlite3 "$DB_PATH" "SELECT 1;" > /dev/null 2>&1; then
        echo "WARNING: $DB_PATH is not a valid SQLite3 database. Skipping changes."
        return 1
    fi
    
    # Check all required tables exist
    for table in "${required_tables[@]}"; do
        TABLE_EXISTS=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$table';" 2>/dev/null)
        if [ "$TABLE_EXISTS" != "1" ]; then
            echo "WARNING: Required table '$table' not found in $DB_PATH. Skipping changes."
            return 1
        fi
    done
    
    return 0
}

# Construct the command line arguments
ARGS=""

# Add sv_port from UDP_RANGE
ARGS="$ARGS -sv_port $BASE_PORT"

# Add map
ARGS="$ARGS +map $MAP"

# Add max players, with validation
if [[ "$MAX_PLAYERS" =~ ^[0-9]+$ ]] && [ "$MAX_PLAYERS" -ge 1 ] && [ "$MAX_PLAYERS" -le 100 ]; then
    ARGS="$ARGS +sv_maxplayers $MAX_PLAYERS"
else
    echo "MAX_PLAYERS must be a number between 1 and 100. Using default of 36."
    ARGS="$ARGS +sv_maxplayers 36"
fi

# Add server ID, with validation
if [[ "$MIS_GAMESERVERID" =~ ^[0-9]+$ ]]; then
    ARGS="$ARGS -mis_gameserverid $MIS_GAMESERVERID"
else
    echo "MIS_GAMESERVERID must be a numeric value. Using default of 100."
    ARGS="$ARGS -mis_gameserverid 100"
fi

# Add whitelist if enabled
WHITELISTED_LOWER=$(echo "$WHITELISTED" | tr '[:upper:]' '[:lower:]')
if [ "$WHITELISTED_LOWER" = "1" ] || [ "$WHITELISTED_LOWER" = "y" ] || [ "$WHITELISTED_LOWER" = "yes" ] || [ "$WHITELISTED_LOWER" = "true" ]; then
    ARGS="$ARGS -mis_whitelist"
fi

# Grant all guides if enabled
GRANT_ALL_GUIDES_LOWER=$(echo "$GRANT_ALL_GUIDES" | tr '[:upper:]' '[:lower:]')
if [ "$GRANT_ALL_GUIDES_LOWER" = "1" ] || [ "$GRANT_ALL_GUIDES_LOWER" = "y" ] || [ "$GRANT_ALL_GUIDES_LOWER" = "yes" ] || [ "$GRANT_ALL_GUIDES_LOWER" = "true" ]; then
    echo "GRANT_ALL_GUIDES is enabled."
    
    # Check database validity and required tables (ServerAccountData and Characters)
    DB_CHECKS_PASSED=1
    _db_check_passed "ServerAccountData" "Characters"
    DB_CHECKS_PASSED=$?
    
    if [ "$DB_CHECKS_PASSED" -eq 0 ]; then
        # Execute SQL to grant all guides and create trigger for future updates
        sqlite3 "$DB_PATH" <<EOF
CREATE TRIGGER IF NOT EXISTS reset_guides_on_character_update
AFTER UPDATE ON Characters
FOR EACH ROW
BEGIN
    UPDATE ServerAccountData 
    SET Guide00="-1", Guide01="-1" 
    WHERE AccountID = NEW.AccountID;
END;

UPDATE ServerAccountData SET Guide00="-1", Guide01="-1";
EOF
        echo "All guides granted successfully."
    fi
fi

# Vehicle limiting based on BASE_VEHICLE_LIMITER
# Because they're quick-despawn vehicles, bicycles, tractors, quadbikes, and jetskis
# are excluded from the limiting process
if [[ "${BASE_VEHICLE_LIMITER}" =~ ^[0-9]+$ ]] && [ "${BASE_VEHICLE_LIMITER}" -ge 0 ]; then
    echo "Vehicle limiter enabled: keeping $BASE_VEHICLE_LIMITER closest vehicle(s) per PlotSign"
    
    # Check database validity and required tables (Vehicles and Structures)
    DB_CHECKS_PASSED=1
    _db_check_passed "Vehicles" "Structures"
    DB_CHECKS_PASSED=$?
    
    if [ "$DB_CHECKS_PASSED" -eq 0 ]; then
        # Execute vehicle pruning SQL (similar to prune_vehicles.sh but with variable limit)
        sqlite3 "$DB_PATH" <<EOF
DELETE FROM Vehicles
WHERE ClassName NOT IN ('tractor', 'quadbike', 'jetski', 'bicycle')
AND VehicleID IN (
    SELECT vehicle_id FROM (
        SELECT 
            v.VehicleID AS vehicle_id,
            ROW_NUMBER() OVER (
                PARTITION BY s.StructureID 
                ORDER BY sqrt(pow(v.PosX - s.PosX, 2) + pow(v.PosY - s.PosY, 2)) ASC
            ) AS rn
        FROM Vehicles v
        INNER JOIN Structures s ON s.ClassName = 'PlotSign'
        WHERE v.ClassName NOT IN ('tractor', 'quadbike', 'jetski', 'bicycle')
        AND sqrt(pow(v.PosX - s.PosX, 2) + pow(v.PosY - s.PosY, 2)) <= 30
    )
    WHERE rn > $BASE_VEHICLE_LIMITER
);
EOF
        echo "Vehicle limiting complete."
    fi
fi

# Replace sv_maxuptime with a random value between 8 and 12 if VARIABLE_RESTARTS is enabled
VARIABLE_RESTARTS_LOWER=$(echo "$VARIABLE_RESTARTS" | tr '[:upper:]' '[:lower:]')
if [ "$VARIABLE_RESTARTS_LOWER" = "1" ] || [ "$VARIABLE_RESTARTS_LOWER" = "y" ] || [ "$VARIABLE_RESTARTS_LOWER" = "yes" ] || [ "$VARIABLE_RESTARTS_LOWER" = "true" ]; then
    RANDOM_MAXUPTIME=$(awk "BEGIN{srand(); printf \"%.1f\", 8 + (rand() * 4)}")
    ARGS="$ARGS +sv_maxuptime $RANDOM_MAXUPTIME"
    echo "Variable restarts enabled: sv_maxuptime set to $RANDOM_MAXUPTIME"
fi

# Add steam_authtoken, if set, to the command line arguments
# This is useful for servers that require Steam authentication for
# certain features or services, but it's optional and can be left
# empty if not needed. Most servers will not require this, but if you
# have a Steam Auth Token, you can set it in the environment variable
# STEAM_AUTH_TOKEN.
if [ -n "$STEAM_AUTH_TOKEN" ]; then
    ARGS="$ARGS +steam_authtoken ${STEAM_AUTH_TOKEN}"
fi

# Add http start server
ARGS="$ARGS +http_startserver"

# Remove the appmanifest file to force SteamCMD to re-validate the installation on each run
rm -f /server/steamapps/appmanifest_302200.acf

# Install the Miscreated server - retrying on failure (bounded to avoid an infinite loop)
STEAMCMD_MAX_ATTEMPTS=${STEAMCMD_MAX_ATTEMPTS:-10}
STEAMCMD_ATTEMPT=0
while :; do
    STEAMCMD_ATTEMPT=$((STEAMCMD_ATTEMPT + 1))
    if /opt/steamcmd/steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir /server +login anonymous +app_update 302200 validate +quit; then
        break
    fi
    echo "SteamCMD failed (attempt $STEAMCMD_ATTEMPT of $STEAMCMD_MAX_ATTEMPTS)."
    if [ "$STEAMCMD_ATTEMPT" -ge "$STEAMCMD_MAX_ATTEMPTS" ]; then
        echo "ERROR: SteamCMD failed after $STEAMCMD_MAX_ATTEMPTS attempts. Giving up."
        exit 1
    fi
    echo "Retrying in 5 seconds..."
    sleep 5
done

# Append supplemental config to system.cfg if it exists (idempotent:
# the block is only added once, marked with BEGIN/END markers).
SUPP_BEGIN_MARKER="# BEGIN system.cfg.supplemental (auto-appended)"
SUPP_END_MARKER="# END system.cfg.supplemental (auto-appended)"
if [ -f /server/system.cfg.supplemental ]; then
    if [ -f /server/system.cfg ] && grep -qF "$SUPP_END_MARKER" /server/system.cfg; then
        echo "Supplemental config already present in system.cfg. Skipping append."
    else
        # Normalize to LF for editing, append the block, restore CRLF afterwards
        sed -i 's/\r$//' /server/system.cfg
        echo "" >> /server/system.cfg
        echo "$SUPP_BEGIN_MARKER" >> /server/system.cfg
        cat /server/system.cfg.supplemental >> /server/system.cfg
        echo "$SUPP_END_MARKER" >> /server/system.cfg
        echo "" >> /server/system.cfg
        sed -i 's/$/\r/' /server/system.cfg
        echo "Supplemental config appended to system.cfg."
    fi
fi

# Start the Miscreated server with Wine
echo "Starting Miscreated Server with command: MiscreatedServer.exe $ARGS"
xvfb-run --auto-servernum sh -c "wine /server/Bin64_dedicated/MiscreatedServer.exe $ARGS"
