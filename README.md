This script monitors a VPN container and its associated sub-containers. It checks if a specified URL is up, and if not, it attempts to restart the VPN container (if needed) and any sub-containers that are part of the VPN network.
The script uses Docker labels to identify sub-containers that are associated with the VPN. It logs all actions taken and is designed to be fault-tolerant, handling cases where sub-containers may crash and receive new container IDs.

To use this script, ensure that all sub-containers are created with a specific label that marks them as part of the VPN network. For example, use '--label vpn_network=true' when running 'docker run' to create a container. This label will be used by the script to identify and manage the appropriate containers.

What the script does:

- **Monitors a VPN container and its sub-containers:** The script keeps an eye on a main VPN container and associated sub-containers.
- **Checks a specified URL:** It verifies if a particular URL is accessible and logs the status.
- **Restarts containers if necessary:** If the URL is not up, the script attempts to restart the VPN container and any sub-containers that are part of the VPN network.
- **Uses Docker labels:** To work correctly, all sub-containers must be created with a specific label (vpn_network=true). It identifies sub-containers associated with the VPN by their Docker labels.
- **Logging:** All actions taken by the script are logged for review. It contains a function to log messages and print them to the console, including rotating logs daily.
- **Fault-tolerant design:** The script is designed to handle cases where sub-containers may crash and receive new container IDs.
- **Configuration section:** The script includes a configuration section where variables like the VPN container name, site URL, log directory, and others are defined.
- **Docker command execution:** There’s a function to execute Docker commands and verify their success.
- **Container start-up wait:** A function is included to wait for a container to start, with a maximum wait time and verify when it's up.
- **External IP, Hostname, and Location fetch:** The script can fetch and print the VPN connection’s external IP, hostname, and location.
- **Sub-container management:** Functions are present to manage sub-containers, including starting and restarting them as needed.
- **Running container check:** The script can check if a container is running and take action if it’s not.
- **Retry mechanism:** A main loop allows for a maximum number of retries before aborting the script if the specified URL remains down.

The script is an attempt to create a well-structured and easy-to-read solution that includes error handling and logging to ensure smooth operation of the VPN and its sub-containers. It’s designed to be run periodically or as needed to ensure the VPN network’s containers are functioning correctly.
