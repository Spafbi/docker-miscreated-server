#!/bin/bash

# Function to read existing value from .env file
get_existing_value() {
    local var_name=$1
    if [ -f ".env" ]; then
        # Extract the value for the variable from .env file
        local value=$(grep "^$var_name=" ".env" | cut -d'=' -f2-)
        if [ -n "$value" ]; then
            echo "$value"
            return 0
        fi
    fi
    return 1
}

# Function to validate MAX_PLAYERS (1-100)
validate_max_players() {
    local value=$1
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 100 ]; then
        echo "Error: MAX_PLAYERS must be a number between 1 and 100"
        return 1
    fi
    return 0
}

# Function to validate MIS_GAMESERVERID (positive 16-bit number)
validate_game_server_id() {
    local value=$1
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        echo "Error: MIS_GAMESERVERID must be a positive 16-bit number (1-65535)"
        return 1
    fi
    return 0
}

# Function to validate boolean values
validate_boolean() {
    local value=$1
    if [[ "$value" != "0" && "$value" != "1" ]]; then
        echo "Error: Boolean values must be 0 or 1"
        return 1
    fi
    return 0
}

# Get existing values from .env if file exists
GRANT_ALL_GUIDES_DEFAULT=$(get_existing_value "GRANT_ALL_GUIDES" || echo "0")
MAP_DEFAULT=$(get_existing_value "MAP" || echo "islands")
MAX_PLAYERS_DEFAULT=$(get_existing_value "MAX_PLAYERS" || echo "36")
MIS_GAMESERVERID_DEFAULT=$(get_existing_value "MIS_GAMESERVERID" || echo "100")
SAVE_DIR_DEFAULT=$(get_existing_value "SAVE_DIR" || echo "$(pwd)")
BASE_PORT_DEFAULT=$(get_existing_value "BASE_PORT" || echo "64090")
WHITELISTED_DEFAULT=$(get_existing_value "WHITELISTED" || echo "0")
IMAGE_DEFAULT=$(get_existing_value "IMAGE" || echo "miscreated")

# Function to get user input with default value
get_input() {
    local prompt=$1
    local default=$2
    local var_name=$3
    
    read -p "$prompt [$default]: " input
    input=${input:-$default}
    
    # Validate input based on variable type
    case $var_name in
        "MAX_PLAYERS")
            if ! validate_max_players "$input"; then
                echo "Invalid input for $var_name. Using default value."
                input=$default
            fi
            ;;
        "MIS_GAMESERVERID")
            if ! validate_game_server_id "$input"; then
                echo "Invalid input for $var_name. Using default value."
                input=$default
            fi
            ;;
        "GRANT_ALL_GUIDES"|"WHITELISTED")
            if ! validate_boolean "$input"; then
                echo "Invalid input for $var_name. Using default value."
                input=$default
            fi
            ;;
    esac
    
    echo "$input"
}

echo "Miscreated Server Configuration"
echo "==============================="

# Prompt for each variable
GRANT_ALL_GUIDES=$(get_input "Grant all guides" $GRANT_ALL_GUIDES_DEFAULT "GRANT_ALL_GUIDES")
MAP=$(get_input "Map" $MAP_DEFAULT "MAP")
MAX_PLAYERS=$(get_input "Maximum players" $MAX_PLAYERS_DEFAULT "MAX_PLAYERS")
MIS_GAMESERVERID=$(get_input "Game server ID" $MIS_GAMESERVERID_DEFAULT "MIS_GAMESERVERID")
SAVE_DIR=$(get_input "Save directory" $SAVE_DIR_DEFAULT "SAVE_DIR")
BASE_PORT=$(get_input "Base port" $BASE_PORT_DEFAULT "BASE_PORT")
WHITELISTED=$(get_input "Whitelisted" $WHITELISTED_DEFAULT "WHITELISTED")
IMAGE=$(get_input "Docker image" $IMAGE_DEFAULT "IMAGE")

# Create .env file
cat > .env << EOF
GRANT_ALL_GUIDES=$GRANT_ALL_GUIDES
MAP=$MAP
MAX_PLAYERS=$MAX_PLAYERS
MIS_GAMESERVERID=$MIS_GAMESERVERID
SAVE_DIR=$SAVE_DIR
BASE_PORT=$BASE_PORT
WHITELISTED=$WHITELISTED
IMAGE=$IMAGE
EOF

echo ""
echo "Configuration saved to .env file"
echo ""
echo "Generated .env content:"
cat .env

# Check if hosting.cfg exists
if [ -f "hosting.cfg" ]; then
    echo "hosting.cfg already exists, skipping creation"
else
    # Copy the example file to hosting.cfg
    cp hosting.cfg.example hosting.cfg

    # Check if the file was created successfully
    if [ -f "hosting.cfg" ]; then
        echo "hosting.cfg created successfully"
    else
        echo "Error: Failed to create hosting.cfg"
        exit 1
    fi
fi

# Read http_password from hosting.cfg
http_password=$(grep "^http_password" hosting.cfg | cut -d'=' -f2)

# Check if http_password contains REPLACE_WITH_RCON_PASSWORD (partial match)
if [[ "$http_password" == *REPLACE_WITH_RCON_PASSWORD* ]]; then
    # Prompt user for RCON password
    read -p "Enter password to use for RCON: " rcon_password

    # Replace the http_password value with the user's input
    sed -i "s/^http_password=.*/http_password=$rcon_password/" hosting.cfg
fi

# Read sv_servername from hosting.cfg
sv_servername=$(grep "^sv_servername" hosting.cfg | cut -d'=' -f2)

# Check if sv_servername contains REPLACE_WITH_SERVERNAME (partial match)
if [[ "$sv_servername" == *REPLACE_WITH_SERVERNAME* ]]; then
    # Prompt user for server name
    read -p "Enter server name: " server_name

    # Encapsulate the server name in quotes and replace the sv_servername value
    sed -i "s/^sv_servername=.*/sv_servername=\"$server_name\"/" hosting.cfg
fi

# Check if Docker image exists
if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^$IMAGE:"; then
    echo "Docker image $IMAGE not found. Building image..."
    docker build --network=host -t "$IMAGE" --build-arg UID=$(id -u) --build-arg GID=$(id -g) .
    if [ $? -ne 0 ]; then
        echo "Error: Failed to build Docker image $IMAGE"
        exit 1
    fi
    echo "Docker image $IMAGE built successfully"
else
    echo "Docker image $IMAGE already exists"
fi

# Create directories in SAVE_DIR
dirs=("DatabaseBackups" "logbackups" "logs")
for dir in "${dirs[@]}"; do
    mkdir -p "$SAVE_DIR/$dir" || { echo "Error: Failed to create $SAVE_DIR/$dir"; exit 1; }
done

# Touch files in SAVE_DIR
files=("banned.xml" "hosting.cfg" "miscreated.db" "reservations.xml" "server.log" "whitelist.xml")
for file in "${files[@]}"; do
    if [ ! -f "$SAVE_DIR/$file" ]; then
        touch "$SAVE_DIR/$file" || { echo "Error: Failed to create $SAVE_DIR/$file"; exit 1; }
    fi
done

echo ""
echo "Setup complete!"
echo ""
echo "You can now customize your server by editing the hosting.cfg file."
echo ""
echo "When you are ready, you can start the server by running the following command:"
echo "docker compose up -d"