#!/bin/bash

# This script monitors a VPN container and its associated sub-containers. It checks if a specified URL is up,
# and if not, it attempts to restart the VPN container and any sub-containers that are part of the VPN network.
# The script uses Docker labels to identify sub-containers that are associated with the VPN.
# It logs all actions taken and is designed to be fault-tolerant, handling cases where sub-containers may crash
# and receive new container IDs.

# To use this script, ensure that all sub-containers are created with a specific label that marks them as part
# of the VPN network. For example, use '--label vpn_network=true' when running 'docker run' to create a container, or add a label through the docker GUI (Key = vpn_network, value = true).
# This label will be used by the script to identify and manage the appropriate containers.

# VPN Container = A container used as a VPN client to connect to your VPN service such as hotio/base or binhex/<appname>vpn
# Sub container = Containers that uses the VPN Container is its network instead of default docker network or your custom network. Instead they use network container:<VPN Container> as its name

# Configuration
VPN_CONTAINER="YOUR_VPN_CONTAINER" # The name of the main VPN container.
SITE_URL="https://your.url.com" # URL to check the status of a site of one of your sub containers.
LOG_DIR="/desired/path/to/logs" # Directory to store log files.
LOG_FILE_PREFIX="restart_vpn_containers" # Log file prefix.
MAX_WAIT_TIME=30 # Max time to wait for a container to start in seconds.
WAIT_INTERVAL=3 # Time interval to check the container status in seconds.
MAX_RETRY_COUNT=3 # Maximum number of retries of the script before aborting
SLEEP_TIME=15 # Wait time (in seconds) before doing final validation of URL check after sub-containers have been started/restarted

# Function to log messages and print to console
log_message() {
    local message="$1"
    local current_date="$(date +%Y%m%d)"
    local log_file_name="${LOG_FILE_PREFIX}_${current_date}.log"

    # Check if a new day has started and rotate log if necessary
    if [[ ! -f "$LOG_DIR/${log_file_name}" ]]; then
        # Archive the old log file
        local old_log_file_name="${LOG_FILE_PREFIX}_$(date -d "yesterday" +%Y%m%d).log"

        if [[ -f "$LOG_DIR/${old_log_file_name}" ]]; then
            mv "$LOG_DIR/${old_log_file_name}" "$LOG_DIR/archive/${old_log_file_name}"
        fi
    fi

    # Append the message to the log file
    echo "$(date) - $message" | tee -a "$LOG_DIR/$log_file_name"
}


# Function to execute Docker commands and verify success
docker_command() {
    local command=$1
    local args=${@:2}
    local output=$(docker $command $args 2>&1)
    local status=$?

    # Log the command and its output
    log_message "Command: docker $command $args"
    log_message "Output: $output"

    # Return the status of the Docker command
    return $status
}

# Function to wait for a container to start
wait_for_container() {
    local container_name=$1
    local elapsed_time=0

    while [[ "$(docker inspect --format '{{.State.Running}}' "$container_name")" != "true" ]]; do
        if [[ $elapsed_time -ge $MAX_WAIT_TIME ]]; then
            log_message "Timeout waiting for container $container_name to start."
            return 1
        fi
        sleep $WAIT_INTERVAL
        ((elapsed_time+=WAIT_INTERVAL))
    done
    log_message "Container $container_name is now running."
}

# Function to fetch and print external IP, Hostname, and Location
fetch_and_print_ip_info() {
    IP_INFO=$(docker exec "$VPN_CONTAINER" curl -s ipinfo.io)
    IP_ADDRESS=$(echo "$IP_INFO" | jq -r '.ip')
    HOSTNAME=$(echo "$IP_INFO" | jq -r '.hostname')
    LOCATION=$(echo "$IP_INFO" | jq -r '.city')
    log_message "VPN Connection >> External IP: $IP_ADDRESS | Hostname: $HOSTNAME | Location: $LOCATION"
}

# Function to check if the URL is up
check_URL_is_up() {
    STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}\n" "$SITE_URL")
    if [[ "$STATUS_CODE" == "502" ]]; then
        log_message "**Containers using VPN is NOT WORKING. Executing script to restart VPN container and its sub-containers.**"
        return 1 # Site is down, return 1 to indicate error
    else
        log_message "**Containers using VPN is WORKING.**"
        return 0 # Site is up or any other status code, return 0 to indicate success
    fi
}

get_sub_containers() {
    # Use the Docker CLI to filter containers by label
    docker ps -aq --filter "label=vpn_network=true" | xargs -I {} docker inspect --format '{{.Name}}' {} | sed 's/^\///'
}

# Function to restart the VPN container
restart_vpn_container() {
    log_message "Restarting VPN container..."
    docker_command restart "$VPN_CONTAINER"
    wait_for_container "$VPN_CONTAINER"
    fetch_and_print_ip_info
}

# Function to check and restart the VPN container if needed
check_vpn_container() {
    VPN_CONTAINER_STATUS=$(docker inspect --format '{{.State.Running}}' "$VPN_CONTAINER")
    if [[ "$VPN_CONTAINER_STATUS" == "false" ]]; then
        log_message "VPN container is not currently running. Trying to start it..."
        docker_command start "$VPN_CONTAINER"
        wait_for_container "$VPN_CONTAINER"
    else
        log_message "VPN container is running. Checking connectivity..."
        if ! docker exec "$VPN_CONTAINER" ping -c 1 1.1.1.1 &> /dev/null || ! docker exec "$VPN_CONTAINER" ping -c 1 google.com &> /dev/null; then
            log_message "Connectivity issue detected."
            restart_vpn_container
        else
            log_message "VPN connection is UP. No action needed with VPN Container. Continuing to restart sub-containers..."
        fi
    fi
}

# Function to manage sub-containers
manage_sub_containers() {
    local success=0 # Use 0 for true/success and 1 for false/failure
    CONTAINERS=($(get_sub_containers))
    for CONTAINER in "${CONTAINERS[@]}"; do
        # Check if the container is running and manage it accordingly
        CONTAINER_STATUS=$(docker inspect --format '{{.State.Running}}' "$CONTAINER")
        if [[ "$CONTAINER_STATUS" == "1" ]]; then
            log_message "Starting stopped container: $CONTAINER..."
            if ! docker_command start "$CONTAINER"; then
                success=1
                break
            fi
            wait_for_container "$CONTAINER"
        else
            log_message "Restarting running container: $CONTAINER..."
            if ! docker_command restart "$CONTAINER"; then
                success=1
                break
            fi
            wait_for_container "$CONTAINER"
        fi
    done
    return $success
}

# Function to check if a container is running
is_container_running() {
    local container_name=$1
    local container_status=$(docker inspect -f '{{.State.Status}}' "$container_name")
    [[ "$container_status" == "running" ]]
}

# Main loop with a maximum of MAX_RETRY_COUNT retries
RETRY_COUNT=0
while [[ $RETRY_COUNT -lt $MAX_RETRY_COUNT ]]; do
    # Check if the site is up
    if check_URL_is_up; then
        log_message "VPN Container and sub-containers are UP."
        log_message "Identified sub containers: $(get_sub_containers | tr '\n' ', ')"
        fetch_and_print_ip_info
        exit 0
    else
        log_message "Script starting..."
        # Check and restart the VPN container if necessary
        check_vpn_container

        # Manage sub-containers
        if ! manage_sub_containers; then
            log_message "Failed to start/restart one or more sub-containers. Restarting VPN container..."
            restart_vpn_container
            # Ensure all sub-containers are managed after VPN container restart
            if ! manage_sub_containers; then
                log_message "VPN Container restarted due to failed start/restart of sub containers. Trying to restart sub containers again..."
            fi
        fi

        # Check individual sub-containers
        for CONTAINER in "${CONTAINERS[@]}"; do
            if ! is_container_running "$CONTAINER"; then
                log_message "Sub-container $CONTAINER is not running. Starting it..."
                docker_command start "$CONTAINER"
                wait_for_container "$CONTAINER"
            fi
        done

        log_message "Waiting a moment to allow containers to start up properly..."
        sleep $SLEEP_TIME

        # Check if the site is up again after waiting
        if check_URL_is_up; then
            log_message "VPN Container and sub-containers are UP."
            log_message "Identified containers: $(get_sub_containers | tr '\n' ', ')"
            fetch_and_print_ip_info
            exit 0
        fi

        # Increment the retry count and log it
        ((RETRY_COUNT++))
        log_message "Retry count: $RETRY_COUNT"
    fi
done

log_message "VPN Containers and/or the sub-containers are STILL DOWN. Maximum retries reached. Aborting script."
