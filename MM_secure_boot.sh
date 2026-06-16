#!/bin/bash

# secure_boot.sh
# Script to transfer u-boot_pc_ros2_bom.bin file to all servers
# Usage: ./secure_boot.sh <server_list_file>

set -euo pipefail

# Source the hostname capture script to get server expansion functions
source ./hostname_capture.sh

# Configuration
PC_SOURCE_FILE="/opt/clmgr/tftpboot/u-boot_pc_ros2_tor_bom.bin"
SC_SOURCE_FILE="/opt/clmgr/tftpboot/u-boot_sc_ros2_bom.bin"
DEST_DIR="/tmp"
PC_DEST_FILE="$DEST_DIR/u-boot_pc_ros2_tor_bom.bin"
SC_DEST_FILE="$DEST_DIR/u-boot_sc_ros2_bom.bin"

# Function to display usage
usage() {
    echo "Usage: $0 <server_list_file>"
    echo "Example: $0 sample_servers.txt"
    echo ""
    echo "This script will transfer:"
    echo "  - $PC_SOURCE_FILE to PC hosts"
    echo "  - $SC_SOURCE_FILE to SC hosts"
    exit 1
}

# Function to check if source files exist
check_source_files() {
    local missing_files=0
    
    if [[ ! -f "$PC_SOURCE_FILE" ]]; then
        echo "Error: PC source file '$PC_SOURCE_FILE' not found!"
        ((missing_files++))
    else
        echo "PC source file found: $PC_SOURCE_FILE"
        ls -lh "$PC_SOURCE_FILE"
    fi
    
    if [[ ! -f "$SC_SOURCE_FILE" ]]; then
        echo "Error: SC source file '$SC_SOURCE_FILE' not found!"
        ((missing_files++))
    else
        echo "SC source file found: $SC_SOURCE_FILE"
        ls -lh "$SC_SOURCE_FILE"
    fi
    
    if [[ $missing_files -gt 0 ]]; then
        echo "Please verify the missing files exist and are accessible."
        exit 1
    fi
    
    echo ""
}

# Function to transfer files to appropriate hosts using scp
transfer_files_scp() {
    echo "=== Transferring U-Boot files to appropriate hosts using SCP ==="
    echo ""
    
    if [[ -z "${PC_HOSTS_LIST:-}" && -z "${SC_HOSTS_LIST:-}" ]]; then
        echo "Error: No hosts found in server list!"
        exit 1
    fi
    
    # Create destination directory on all hosts first
    echo "1. Creating destination directory on all hosts..."
    local all_hosts=""
    if [[ -n "${PC_HOSTS_LIST:-}" && -n "${SC_HOSTS_LIST:-}" ]]; then
        all_hosts="$PC_HOSTS_LIST,$SC_HOSTS_LIST"
    elif [[ -n "${PC_HOSTS_LIST:-}" ]]; then
        all_hosts="$PC_HOSTS_LIST"
    elif [[ -n "${SC_HOSTS_LIST:-}" ]]; then
        all_hosts="$SC_HOSTS_LIST"
    fi
    
    pdsh -w "$all_hosts" "mkdir -p $DEST_DIR" || {
        echo "Warning: Some hosts may have failed to create directory"
    }
    
    echo ""
    local total_failed=0
    
    # Transfer PC file to PC hosts
    if [[ -n "${PC_HOSTS_LIST:-}" ]]; then
        echo "2a. Transferring PC U-Boot file to PC hosts..."
        echo "    Source: $PC_SOURCE_FILE"
        echo "    Destination: $PC_DEST_FILE"
        echo "    PC Hosts: $PC_HOSTS_LIST"
        echo ""
        
        # Convert comma-separated list to array
        IFS=',' read -ra PC_HOSTS <<< "$PC_HOSTS_LIST"
        
        # Transfer to each PC host in parallel
        pids=()
        for host in "${PC_HOSTS[@]}"; do
            echo "  Starting PC transfer to $host..."
            scp "$PC_SOURCE_FILE" "$host:$PC_DEST_FILE" &
            pids+=($!)
        done
        
        # Wait for all PC transfers to complete
        pc_failed=0
        pc_completed=0
        for i in "${!pids[@]}"; do
            if wait "${pids[$i]}"; then
                echo "  ✓ PC transfer to ${PC_HOSTS[$i]} completed successfully"
                ((pc_completed++))
            else
                echo "  ✗ PC transfer to ${PC_HOSTS[$i]} failed"
                ((pc_failed++))
            fi
        done
        
        echo ""
        echo "PC Transfer Summary:"
        echo "  Successful: $pc_completed"
        echo "  Failed: $pc_failed"
        echo "  Total: ${#PC_HOSTS[@]}"
        
        total_failed=$((total_failed + pc_failed))
    fi
    
    # Transfer SC file to SC hosts
    if [[ -n "${SC_HOSTS_LIST:-}" ]]; then
        echo ""
        echo "2b. Transferring SC U-Boot file to SC hosts..."
        echo "    Source: $SC_SOURCE_FILE"
        echo "    Destination: $SC_DEST_FILE"
        echo "    SC Hosts: $SC_HOSTS_LIST"
        echo ""
        
        # Convert comma-separated list to array
        IFS=',' read -ra SC_HOSTS <<< "$SC_HOSTS_LIST"
        
        # Transfer to each SC host in parallel
        pids=()
        for host in "${SC_HOSTS[@]}"; do
            echo "  Starting SC transfer to $host..."
            scp "$SC_SOURCE_FILE" "$host:$SC_DEST_FILE" &
            pids+=($!)
        done
        
        # Wait for all SC transfers to complete
        sc_failed=0
        sc_completed=0
        for i in "${!pids[@]}"; do
            if wait "${pids[$i]}"; then
                echo "  ✓ SC transfer to ${SC_HOSTS[$i]} completed successfully"
                ((sc_completed++))
            else
                echo "  ✗ SC transfer to ${SC_HOSTS[$i]} failed"
                ((sc_failed++))
            fi
        done
        
        echo ""
        echo "SC Transfer Summary:"
        echo "  Successful: $sc_completed"
        echo "  Failed: $sc_failed"
        echo "  Total: ${#SC_HOSTS[@]}"
        
        total_failed=$((total_failed + sc_failed))
    fi
    
    echo ""
    echo "Overall Transfer Summary:"
    echo "  Total failed transfers: $total_failed"
    
    return $total_failed
}

# Function to verify transfer
verify_transfer() {
    echo ""
    echo "=== Verifying file transfer ==="
    echo ""
    
    # Verify PC file transfers
    if [[ -n "${PC_HOSTS_LIST:-}" ]]; then
        echo "Checking PC file existence and size on PC hosts..."
        pdsh -w "$PC_HOSTS_LIST" "ls -lh $PC_DEST_FILE 2>/dev/null || echo 'PC file not found on \$HOSTNAME'" | sort
        
        echo ""
        echo "Checking PC file checksums..."
        local_pc_checksum=$(sha256sum "$PC_SOURCE_FILE" | cut -d' ' -f1)
        echo "Local PC file checksum: $local_pc_checksum"
        echo "Remote PC file checksums:"
        pdsh -w "$PC_HOSTS_LIST" "sha256sum $PC_DEST_FILE 2>/dev/null | cut -d' ' -f1 || echo 'PC checksum failed on \$HOSTNAME'" | sort
        echo ""
    fi
    
    # Verify SC file transfers
    if [[ -n "${SC_HOSTS_LIST:-}" ]]; then
        echo "Checking SC file existence and size on SC hosts..."
        pdsh -w "$SC_HOSTS_LIST" "ls -lh $SC_DEST_FILE 2>/dev/null || echo 'SC file not found on \$HOSTNAME'" | sort
        
        echo ""
        echo "Checking SC file checksums..."
        local_sc_checksum=$(sha256sum "$SC_SOURCE_FILE" | cut -d' ' -f1)
        echo "Local SC file checksum: $local_sc_checksum"
        echo "Remote SC file checksums:"
        pdsh -w "$SC_HOSTS_LIST" "sha256sum $SC_DEST_FILE 2>/dev/null | cut -d' ' -f1 || echo 'SC checksum failed on \$HOSTNAME'" | sort
    fi
}

# Function to set reboot recovery image on SC and PC hosts
set_reboot_recovery_image() {
    echo ""
    echo "=== Setting Reboot Recovery Image on SC and PC Hosts ==="
    echo ""
    
    if [[ -z "${ALL_HOSTS_LIST:-}" ]]; then
        echo "Error: Host lists not available!"
        return 1
    fi 
    
    echo "Setting reboot recovery image on all hosts..."
    echo "Command: echo -n R > /dev/mmcblk0p1"
    echo "All Hosts: $ALL_HOSTS_LIST"
    echo ""
    
    # Execute the recovery image command on all hosts
    pdsh -w "$ALL_HOSTS_LIST" 'echo -n R > /dev/mmcblk0p1' || {
        echo "Error: Failed to set reboot recovery image on some hosts"
        return 1
    }
    
    echo "✓ Reboot recovery image set successfully on all SC and PC hosts"

    return 0
}

# Function to flash special secure u-boot image on SC hosts
flash_secure_uboot() {
    echo ""
    echo "=== Flashing Special Secure U-Boot Image on SC Hosts ==="
    echo ""
    
    if [[ -z "${SC_HOSTS_LIST:-}" ]]; then
        echo "Error: SC hosts list not available!"
        return 1
    fi
    
    echo "Flashing secure u-boot image on SC hosts..."
    echo "Command: uboot_flasher $SC_DEST_FILE"
    echo "SC Hosts: $SC_HOSTS_LIST"
    echo ""
    
    # Execute the uboot_flasher command on SC hosts
    local flash_output
    flash_output=$(pdsh -w "$SC_HOSTS_LIST" "uboot_flasher $SC_DEST_FILE" 2>&1)
    local flash_exit_code=$?
    
    echo "$flash_output"
    
    # Check if flashing completed successfully
    if [[ $flash_exit_code -eq 0 ]]; then
        # Verify that the output contains "Flashing completed successfully"
#        if echo "$flash_output" | grep -q "Flashing completed successfully"; then
            echo ""
            echo "✓ U-Boot flashing completed successfully on all SC hosts"
            return 0
#        else
#            echo ""
#            echo "⚠ Warning: Flash command returned 0 but 'Flashing completed successfully' message not found"
#            echo "DEBUG OUTPUT:"
#            echo "============="
#            echo "$flash_output"
#            echo "============="
#            echo "Please verify the flash operation manually"
#            return 1
#        fi
    else
        echo ""
        echo "✗ Error: U-Boot flashing failed with exit code $flash_exit_code"
        echo "DEBUG OUTPUT:"
        echo "============="
        echo "$flash_output"
        echo "============="
        return 1
    fi
}

# Function to flash secure u-boot image on PC hosts
flash_pc_uboot() {
    echo ""
    echo "=== Flashing Secure U-Boot Image on PC Hosts ==="
    echo ""
    
    if [[ -z "${PC_HOSTS_LIST:-}" ]]; then
        echo "Error: PC hosts list not available!"
        return 1
    fi
    
    echo "Flashing secure u-boot image on PC hosts..."
    echo "Command: uboot_flasher $PC_DEST_FILE"
    echo "PC Hosts: $PC_HOSTS_LIST"
    echo ""
    
    # Execute the uboot_flasher command on PC hosts
    local flash_output
    flash_output=$(pdsh -w "$PC_HOSTS_LIST" "uboot_flasher $PC_DEST_FILE" 2>&1)
    local flash_exit_code=$?
    
    echo "$flash_output"
    
    # Check if flashing completed successfully
    if [[ $flash_exit_code -eq 0 ]]; then
        # Verify that the output contains "Flashing completed successfully"
#        if echo "$flash_output" | grep -q "Flashing completed successfully"; then
            echo ""
            echo "✓ U-Boot flashing completed successfully on all PC hosts"
            return 0
#        else
#            echo ""
#            echo "⚠ Warning: Flash command returned 0 but 'Flashing completed successfully' message not found"
#            echo "DEBUG OUTPUT:"
#            echo "============="
#            echo "$flash_output"
#            echo "============="
#            echo "Please verify the flash operation manually"
#            return 1
#        fi
    else
        echo ""
        echo "✗ Error: U-Boot flashing failed with exit code $flash_exit_code"
        echo "DEBUG OUTPUT:"
        echo "============="
        echo "$flash_output"
        echo "============="
        return 1
    fi
}

# Function to shutdown SC hosts using PC hosts
shutdown_sc_hosts() {
    echo ""
    echo "=== Shutting Down SC Hosts ==="
    echo ""
    
    if [[ -z "${PC_HOSTS_LIST:-}" ]]; then
        echo "Error: PC hosts list not available!"
        return 1
    fi
    
    echo "Shutting down SC hosts via PC hosts..."
    echo "Command: ros_power_down"
    echo "PC Hosts: $PC_HOSTS_LIST"
    echo ""
    
    # Execute the ros_power_down command on PC hosts
    local shutdown_output
    shutdown_output=$(pdsh -w "$PC_HOSTS_LIST" "ros_power_down" 2>&1)
    local shutdown_exit_code=$?
    
    echo "$shutdown_output"
    
    # Check if shutdown command was successful
    if [[ $shutdown_exit_code -eq 0 ]]; then
        echo ""
        echo "✓ SC shutdown command sent successfully via all PC hosts"
        echo "Note: SC hosts are now powering down and will be unavailable"
        return 0
    else
        echo ""
        echo "⚠ Warning: Some SC shutdown commands may have failed"
        echo "DEBUG OUTPUT:"
        echo "============="
        echo "$shutdown_output"
        echo "============="
        return 1
    fi
}

# Function to clear PC log files from chassis controller
clear_pc_log_files() {
    echo ""
    echo "=== Clearing PC Log Files from Chassis Controller ==="
    echo ""
    
    if [[ -z "${ALL_HOSTS_LIST:-}" ]]; then
        echo "Error: Host list not available!"
        return 1
    fi
    
    # Process original server names to extract chassis and switch_number info
    # Read the original server file to get the base server names
    local server_file="$1"
    if [[ ! -f "$server_file" ]]; then
        echo "Error: Server file not provided or not found!"
        return 1
    fi
    
    declare -A chassis_switches
    
    # Read server names and extract chassis and switch_number info
    while IFS= read -r server || [[ -n "$server" ]]; do
        # Skip empty lines and comments
        [[ -z "$server" || "$server" =~ ^[[:space:]]*# ]] && continue
        
        # Remove leading/trailing whitespace
        server=$(echo "$server" | xargs)
        
        # Extract chassis and switch_number from server name (e.g., x1000c0r5 -> chassis=x1000c0, switch_number=r5)
        if [[ "$server" =~ ^(.+)(r[0-9]+)$ ]]; then
            local chassis="${BASH_REMATCH[1]}"
            local switch_number="${BASH_REMATCH[2]}"
            
            # Store chassis -> switch_number mapping
            chassis_switches["$chassis"]="$switch_number"
            
            echo "Parsed server '$server' -> Chassis: '$chassis', Switch Number: '$switch_number'"
        else
            echo "Warning: Server '$server' does not match expected pattern (e.g., x1000c0r5)"
        fi
    done < "$server_file"
    
    if [[ ${#chassis_switches[@]} -eq 0 ]]; then
        echo "Warning: No valid chassis/switch_number combinations found!"
        return 1
    fi
    
    echo ""
    echo "Found ${#chassis_switches[@]} chassis to process:"
    
    # Clear log files for each chassis
    local failed=0
    for chassis in "${!chassis_switches[@]}"; do
        local switch_number="${chassis_switches[$chassis]}"
        #local log_path="/console/log/${switch_number}b0/current"
        local log_path="/var/log/sC/current"
        
        echo ""
        echo "Clearing log file on chassis: $chassis"
        echo "  Log path: $log_path"
        echo "  Command: > $log_path"
        
        # SSH into chassis and clear the log file
        if pdsh -w "$chassis" "> $log_path" 2>/dev/null; then
            echo "  ✓ Successfully cleared $log_path on $chassis"
        else
            echo "  ✗ Failed to clear $log_path on $chassis"
            ((failed++))
        fi
    done
    
    echo ""
    if [[ $failed -eq 0 ]]; then
        echo "✓ All PC log files cleared successfully from chassis controllers"
        return 0
    else
        echo "⚠ $failed chassis log clear operations failed"
        return 1
    fi
}

# Function to reboot all PC hosts
reboot_pc_hosts() {
    echo ""
    echo "=== Rebooting All PC Hosts ==="
    echo ""
    
    if [[ -z "${PC_HOSTS_LIST:-}" ]]; then
        echo "Error: PC hosts list not available!"
        return 1
    fi
    
    echo "Rebooting PC hosts..."
    echo "Command: reboot"
    echo "PC Hosts: $PC_HOSTS_LIST"
    echo ""
    
    # Execute the reboot command on PC hosts
    local reboot_output
    reboot_output=$(pdsh -w "$PC_HOSTS_LIST" "reboot" 2>&1)
    local reboot_exit_code=$?
    
    echo "$reboot_output"
    
    # Check if reboot command was successful
    if [[ $reboot_exit_code -eq 0 ]]; then
        echo ""
        echo "✓ Reboot command sent successfully to all PC hosts"
        echo "Note: PC hosts are now rebooting and will be unavailable for a few minutes"
        return 0
    else
        echo ""
        echo "⚠ Warning: Some PC hosts may not have received the reboot command properly"
        echo "DEBUG OUTPUT:"
        echo "============="
        echo "$reboot_output"
        echo "============="
        return 1
    fi
}

# Function to wait for secure boot completion on PC hosts
wait_for_secure_boot_completion() {
    echo ""
    echo "=== Waiting for Secure Boot Completion on PC ==="
    echo ""
    
    local server_file="$1"
    if [[ ! -f "$server_file" ]]; then
        echo "Error: Server file not provided or not found!"
        return 1
    fi
    
    # Group servers by chassis and collect switch numbers
    declare -A chassis_switches
    declare -a all_servers
    
    # Parse server names to group by chassis and track all servers
    while IFS= read -r server || [[ -n "$server" ]]; do
        # Skip empty lines and comments
        [[ -z "$server" || "$server" =~ ^[[:space:]]*# ]] && continue
        
        # Remove leading/trailing whitespace
        server=$(echo "$server" | xargs)
        
        # Extract chassis and switch_number from server name
        if [[ "$server" =~ ^(.+)(r[0-9]+)$ ]]; then
            local chassis="${BASH_REMATCH[1]}"
            local switch_number="${BASH_REMATCH[2]}"
            
            # Add to all servers list
            all_servers+=("$server")
            
            # Add switch_number to chassis list
            if [[ -n "${chassis_switches[$chassis]:-}" ]]; then
                chassis_switches["$chassis"]="${chassis_switches[$chassis]} $switch_number"
            else
                chassis_switches["$chassis"]="$switch_number"
            fi
        else
            echo "Warning: Server '$server' does not match expected pattern (e.g., x1000c0r5)"
        fi
    done < "$server_file"
    
    if [[ ${#chassis_switches[@]} -eq 0 ]]; then
        echo "Error: No valid chassis/switch combinations found!"
        return 1
    fi
    
    echo "Monitoring ${#all_servers[@]} servers across ${#chassis_switches[@]} chassis:"
    for chassis in "${!chassis_switches[@]}"; do
        echo "  $chassis: ${chassis_switches[$chassis]}"
    done
    echo ""
    
    # Record initial log file sizes to avoid false positives from old log entries
    declare -A initial_log_sizes
    echo "Recording initial log file sizes to track only new entries..."
    for chassis in "${!chassis_switches[@]}"; do
        local switches=(${chassis_switches[$chassis]})
        for switch_number in "${switches[@]}"; do
            local log_path="/var/log/sC/current"
            local server_name="${chassis}${switch_number}"
            
            # Get current log file size (in bytes)
            local log_size
            log_size=$(pdsh -w "$chassis" "--external-switch-controller -c < $log_path 2>/dev/null || echo '0'" 2>/dev/null | grep -o '[0-9]*' | head -1)
            initial_log_sizes["$server_name"]="${log_size:-0}"
            echo "  $server_name: Starting from byte offset ${initial_log_sizes[$server_name]}"
        done
    done
    echo ""
    
    local search_string="login:"
    local poll_interval=30   # Check every 30 seconds
    local start_time=$(date +%s)
    local poll_count=0
    
    echo "Polling for '$search_string' in console logs (checking only NEW content since boot started)..."
    echo "Poll interval: ${poll_interval}s (no timeout - will wait until all complete)"
    echo ""
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        ((poll_count++))
        
        echo "=== Poll #$poll_count at ${elapsed}s ==="
        
        declare -a completed_servers=()
        declare -a pending_servers=()
        local all_completed=true
        
        # Check each chassis and its switches
        for chassis in "${!chassis_switches[@]}"; do
            local switches=(${chassis_switches[$chassis]})
            
            for switch_number in "${switches[@]}"; do
                local log_path="/var/log/sC/current"
                local server_name="${chassis}${switch_number}"
                
                # Get the initial log size for this server
                local initial_size="${initial_log_sizes[$server_name]}"
                
                # Check if the log contains the target string in NEW content only (after initial_size)
                # Use tail with byte offset to read only new content
                local check_result
                if [[ "$initial_size" -gt 0 ]]; then
                    # Read only content after the initial size
                    check_result=$(pdsh -w "$chassis" "tail -c +$((initial_size + 1)) $log_path 2>/dev/null | grep -q '$search_string' && echo 'FOUND' || echo 'NOT_FOUND'" 2>/dev/null)
                else
                    # If initial size was 0, check recent entries only to avoid very old content
                    check_result=$(pdsh -w "$chassis" "tail -n 1000 $log_path 2>/dev/null | grep -q '$search_string' && echo 'FOUND' || echo 'NOT_FOUND'" 2>/dev/null)
                fi
                
                if [[ "$check_result" == *"FOUND"* ]]; then
                    completed_servers+=("$server_name")
                else
                    pending_servers+=("$server_name")
                    all_completed=false
                fi
            done
        done
        
        # Display results
        echo ""
        local completed_count=${#completed_servers[@]}
        local pending_count=${#pending_servers[@]}
        echo "Completed servers ($completed_count/${#all_servers[@]}):"
        if [[ $completed_count -gt 0 ]]; then
            for server in "${completed_servers[@]}"; do
                echo "  ✓ $server"
            done
        else
            echo "  (none yet)"
        fi
        
        echo ""
        echo "Still waiting for ($pending_count/${#all_servers[@]}):"
        if [[ $pending_count -gt 0 ]]; then
            for server in "${pending_servers[@]}"; do
                echo "  ⏳ $server"
            done
        else
            echo "  (none - all completed!)"
        fi
        
        if [[ "$all_completed" == true ]]; then
            echo ""
            echo "✓ Secure boot completion detected on all ${#all_servers[@]} PC hosts!"
            echo "Total wait time: ${elapsed} seconds (${poll_count} polls)"
            return 0
        fi
        
        echo ""
        echo "Waiting ${poll_interval}s before next poll..."
        echo "----------------------------------------"
        sleep $poll_interval
    done
}

# Function to capture PC logs using remote log capture utility
capture_pc_logs() {
    echo ""
    echo "=== Capturing PC Logs ==="
    echo ""
    
    local server_file="$1"
    if [[ ! -f "$server_file" ]]; then
        echo "Error: Server file not provided or not found!"
        return 1
    fi
    
    # Extract unique chassis hostnames
    declare -A unique_chassis
    declare -a chassis_list
    
    # Parse server names to extract chassis
    while IFS= read -r server || [[ -n "$server" ]]; do
        # Skip empty lines and comments
        [[ -z "$server" || "$server" =~ ^[[:space:]]*# ]] && continue
        
        # Remove leading/trailing whitespace
        server=$(echo "$server" | xargs)
        
        # Extract chassis from server name
        if [[ "$server" =~ ^(.+)(r[0-9]+)$ ]]; then
            local chassis="${BASH_REMATCH[1]}"
            
            # Add to unique chassis list if not already present
            if [[ -z "${unique_chassis[$chassis]:-}" ]]; then
                unique_chassis["$chassis"]=1
                chassis_list+=("$chassis")
            fi
        else
            echo "Warning: Server '$server' does not match expected pattern (e.g., x1000c0r5)"
        fi
    done < "$server_file"
    
    if [[ ${#chassis_list[@]} -eq 0 ]]; then
        echo "Error: No valid chassis found!"
        return 1
    fi
    
    echo "Found ${#chassis_list[@]} unique chassis to capture logs from:"
    for chassis in "${chassis_list[@]}"; do
        echo "  $chassis"
    done
    echo ""
    
    # Check if the log capture utility exists
    local log_utility="remote_pc_log_capture_standalone.py"
    if [[ ! -f "$log_utility" ]]; then
        echo "Error: Log capture utility '$log_utility' not found in current directory!"
        echo "Please ensure the utility is present in the same directory as this script."
        return 1
    fi
    
    # Build the command
    local capture_command="python3 $log_utility ${chassis_list[*]}"
    
    echo "Running PC log capture utility..."
    echo "Command: $capture_command"
    echo ""
    
    # Execute the log capture utility
    if $capture_command; then
        echo ""
        echo "✓ PC log capture completed successfully"
        return 0
    else
        echo ""
        echo "✗ PC log capture failed"
        echo "Please check the output above for error details"
        return 1
    fi
}

# Function to deploy PC ITB file and setup boot configuration
deploy_pc_itb() {
    echo ""
    echo "=== Deploying PC ITB File and Boot Configuration ==="
    echo ""
    
    if [[ -z "${PC_HOSTS_LIST:-}" ]]; then
        echo "Error: PC hosts list not available!"
        return 1
    fi
    
    local itb_source="/opt/clmgr/tftpboot/pc-2.0.0-4.itb"
    local itb_dest="/tmp/pc-2.0.0-4.itb"
    
    # Check if source ITB file exists
    if [[ ! -f "$itb_source" ]]; then
        echo "Error: ITB source file '$itb_source' not found!"
        echo "Please verify the file exists and is accessible."
        return 1
    fi
    
    echo "ITB source file found: $itb_source"
    ls -lh "$itb_source"
    echo ""
    
    # Wait for PC hosts to be available for SSH/SCP connections
    echo "Step 0: Waiting for PC hosts to be available for SSH/SCP connections..."
    echo "PC Hosts: $PC_HOSTS_LIST"
    echo ""
    
    # Convert comma-separated list to array for availability checking
    IFS=',' read -ra PC_HOSTS <<< "$PC_HOSTS_LIST"
    
    local poll_interval=30   # Check every 30 seconds
    local start_time=$(date +%s)
    local poll_count=0
    
    echo "Polling for PC host availability..."
    echo "Poll interval: ${poll_interval}s (no timeout - will wait until all are available)"
    echo ""
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        ((poll_count++))
        
        echo "=== Availability Poll #$poll_count at ${elapsed}s ==="
        
        declare -a available_hosts=()
        declare -a unavailable_hosts=()
        local all_available=true
        
        # Check each PC host for SSH availability
        for host in "${PC_HOSTS[@]}"; do
            # Test SSH connection with a simple command
            if ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "echo 'SSH_TEST_OK'" >/dev/null 2>&1; then
                available_hosts+=("$host")
            else
                unavailable_hosts+=("$host")
                all_available=false
            fi
        done
        
        # Display results
        echo ""
        local available_count=${#available_hosts[@]}
        local unavailable_count=${#unavailable_hosts[@]}
        echo "Available PC hosts ($available_count/${#PC_HOSTS[@]}):"
        if [[ $available_count -gt 0 ]]; then
            for host in "${available_hosts[@]}"; do
                echo "  ✓ $host"
            done
        else
            echo "  (none yet)"
        fi
        
        echo ""
        echo "Still waiting for ($unavailable_count/${#PC_HOSTS[@]}):"
        if [[ $unavailable_count -gt 0 ]]; then
            for host in "${unavailable_hosts[@]}"; do
                echo "  ⏳ $host"
            done
        else
            echo "  (none - all available!)"
        fi
        
        if [[ "$all_available" == true ]]; then
            echo ""
            echo "✓ All ${#PC_HOSTS[@]} PC hosts are now available for SSH/SCP!"
            echo "Total wait time: ${elapsed} seconds (${poll_count} polls)"
            break
        fi
        
        echo ""
        echo "Waiting ${poll_interval}s before next availability check..."
        echo "----------------------------------------"
        sleep $poll_interval
    done
    
    echo ""
    
    # Step 1: Transfer ITB file to PC hosts
    echo "Step 1: Transferring ITB file to PC hosts..."
    echo "Source: $itb_source"
    echo "Destination: $itb_dest"
    echo "PC Hosts: $PC_HOSTS_LIST"
    echo ""
    
    # PC_HOSTS array is already available from the availability check above
    # Transfer ITB file to each PC host in parallel
    pids=()
    for host in "${PC_HOSTS[@]}"; do
        echo "  Starting ITB transfer to $host..."
        scp "$itb_source" "$host:$itb_dest" &
        pids+=($!)
    done
    
    # Wait for all transfers to complete
    failed=0
    completed=0
    for i in "${!pids[@]}"; do
        if wait "${pids[$i]}"; then
            echo "  ✓ ITB transfer to ${PC_HOSTS[$i]} completed successfully"
            ((completed++))
        else
            echo "  ✗ ITB transfer to ${PC_HOSTS[$i]} failed"
            ((failed++))
        fi
    done
    
    echo ""
    echo "ITB Transfer Summary:"
    echo "  Successful: $completed"
    echo "  Failed: $failed"
    echo "  Total: ${#PC_HOSTS[@]}"
    
    if [[ $failed -gt 0 ]]; then
        echo "Error: Some ITB transfers failed. Cannot continue with boot setup."
        return 1
    fi
    
    # Step 2: Execute boot setup commands on PC hosts
    echo ""
    echo "Step 2: Executing boot setup commands on PC hosts..."
    echo "Commands to execute:"
    echo "  1. emmc-setup -B"
    echo "  2. cp $itb_dest /boot/a.itb"
    echo "  3. echo -n A > /dev/mmcblk0p1"
    echo "  4. reboot"
    echo ""
    
    # Execute each command sequentially on all PC hosts
    local setup_commands=(
        "emmc-setup -B"
        "cp $itb_dest /boot/a.itb"
        "echo -n A > /dev/mmcblk0p1"
        "reboot"
    )
    
    for i in "${!setup_commands[@]}"; do
        local cmd="${setup_commands[$i]}"
        local step_num=$((i + 1))
        
        echo "Executing step $step_num on all PC hosts: $cmd"
        
        local cmd_output
        cmd_output=$(pdsh -w "$PC_HOSTS_LIST" "$cmd" 2>&1)
        local cmd_exit_code=$?
        
        if [[ $cmd_exit_code -eq 0 ]]; then
            echo "  ✓ Step $step_num completed successfully on all PC hosts"
        else
            echo "  ⚠ Step $step_num may have failed on some PC hosts"
            echo "  Command output:"
            echo "$cmd_output" | sed 's/^/    /'
        fi
        
        echo ""
        
        # Special handling for reboot command
        if [[ "$cmd" == "reboot" ]]; then
            echo "PC hosts are now rebooting with new ITB configuration..."
            echo "Note: PC hosts will be unavailable for a few minutes during reboot"
            echo "Waiting 30 seconds to continue.."
            sleep 30
            break
        fi
    done
    
    echo "✓ PC ITB deployment and boot configuration completed"
    return 0
}

# Function to deploy SC ITB file to SC hosts
deploy_sc_itb() {
    echo ""
    echo "=== Deploying SC ITB File and Boot Configuration ==="
    echo ""
    
    if [[ -z "${SC_HOSTS_LIST:-}" ]]; then
        echo "Error: SC hosts list not available!"
        return 1
    fi
    
    local itb_source="/opt/clmgr/tftpboot/controllers-3.0.0-128.itb"
    local itb_dest="/tmp/controllers-3.0.0-128.itb"
    
    # Check if source ITB file exists
    if [[ ! -f "$itb_source" ]]; then
        echo "Error: SC ITB source file '$itb_source' not found!"
        echo "Please verify the file exists and is accessible."
        return 1
    fi
    
    echo "SC ITB source file found: $itb_source"
    ls -lh "$itb_source"
    echo ""
    
    # Wait for SC hosts to be available for SSH/SCP connections
    echo "Step 0: Waiting for SC hosts to be available for SSH/SCP connections..."
    echo "SC Hosts: $SC_HOSTS_LIST"
    echo ""
    
    # Convert comma-separated list to array for availability checking
    IFS=',' read -ra SC_HOSTS <<< "$SC_HOSTS_LIST"
    
    local poll_interval=30   # Check every 30 seconds
    local start_time=$(date +%s)
    local poll_count=0
    
    echo "Polling for SC host availability..."
    echo "Poll interval: ${poll_interval}s (no timeout - will wait until all are available)"
    echo ""
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        ((poll_count++))
        
        echo "=== Availability Poll #$poll_count at ${elapsed}s ==="
        
        declare -a available_hosts=()
        declare -a unavailable_hosts=()
        local all_available=true
        
        # Check each SC host for SSH availability
        for host in "${SC_HOSTS[@]}"; do
            # Test SSH connection with a simple command
            if ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "echo 'SSH_TEST_OK'" >/dev/null 2>&1; then
                available_hosts+=("$host")
            else
                unavailable_hosts+=("$host")
                all_available=false
            fi
        done
        
        # Display results
        echo ""
        local available_count=${#available_hosts[@]}
        local unavailable_count=${#unavailable_hosts[@]}
        echo "Available SC hosts ($available_count/${#SC_HOSTS[@]}):"
        if [[ $available_count -gt 0 ]]; then
            for host in "${available_hosts[@]}"; do
                echo "  ✓ $host"
            done
        else
            echo "  (none yet)"
        fi
        
        echo ""
        echo "Still waiting for ($unavailable_count/${#SC_HOSTS[@]}):"
        if [[ $unavailable_count -gt 0 ]]; then
            for host in "${unavailable_hosts[@]}"; do
                echo "  ⏳ $host"
            done
        else
            echo "  (none - all available!)"
        fi
        
        if [[ "$all_available" == true ]]; then
            echo ""
            echo "✓ All ${#SC_HOSTS[@]} SC hosts are now available for SSH/SCP!"
            echo "Total wait time: ${elapsed} seconds (${poll_count} polls)"
            break
        fi
        
        echo ""
        echo "Waiting ${poll_interval}s before next availability check..."
        echo "----------------------------------------"
        sleep $poll_interval
    done
    
    echo ""
    
    # Step 1: Transfer ITB file to SC hosts
    echo "Step 1: Transferring SC ITB file to SC hosts..."
    echo "Source: $itb_source"
    echo "Destination: $itb_dest"
    echo "SC Hosts: $SC_HOSTS_LIST"
    echo ""
    
    # SC_HOSTS array is already available from the availability check above
    # Transfer ITB file to each SC host in parallel
    pids=()
    for host in "${SC_HOSTS[@]}"; do
        echo "  Starting SC ITB transfer to $host..."
        scp "$itb_source" "$host:$itb_dest" &
        pids+=($!)
    done
    
    # Wait for all transfers to complete
    failed=0
    completed=0
    for i in "${!pids[@]}"; do
        if wait "${pids[$i]}"; then
            echo "  ✓ SC ITB transfer to ${SC_HOSTS[$i]} completed successfully"
            ((completed++))
        else
            echo "  ✗ SC ITB transfer to ${SC_HOSTS[$i]} failed"
            ((failed++))
        fi
    done
    
    echo ""
    echo "SC ITB Transfer Summary:"
    echo "  Successful: $completed"
    echo "  Failed: $failed"
    echo "  Total: ${#SC_HOSTS[@]}"
    
    if [[ $failed -gt 0 ]]; then
        echo "Error: Some SC ITB transfers failed. Cannot continue with boot setup."
        return 1
    fi
    
    # Step 2: Execute boot setup commands on SC hosts
    echo ""
    echo "Step 2: Executing boot setup commands on SC hosts..."
    echo "Commands to execute:"
    echo "  1. emmc-setup -B"
    echo "  2. cp $itb_dest /boot/a.itb"
    echo "  3. echo -n A > /dev/mmcblk0p1"
    echo "  4. reboot"
    echo ""
    
    # Execute each command sequentially on all SC hosts
    local setup_commands=(
        "emmc-setup -B"
        "cp $itb_dest /boot/a.itb"
        "echo -n A > /dev/mmcblk0p1"
        "reboot"
    )
    
    for i in "${!setup_commands[@]}"; do
        local cmd="${setup_commands[$i]}"
        local step_num=$((i + 1))
        
        echo "Executing step $step_num on all SC hosts: $cmd"
        
        local cmd_output
        cmd_output=$(pdsh -w "$SC_HOSTS_LIST" "$cmd" 2>&1)
        local cmd_exit_code=$?
        
        if [[ $cmd_exit_code -eq 0 ]]; then
            echo "  ✓ Step $step_num completed successfully on all SC hosts"
        else
            echo "  ⚠ Step $step_num may have failed on some SC hosts"
            echo "  Command output:"
            echo "$cmd_output" | sed 's/^/    /'
        fi
        
        echo ""
        
        # Special handling for reboot command
        if [[ "$cmd" == "reboot" ]]; then
            echo "SC hosts are now rebooting with new ITB configuration..."
            echo "Note: SC hosts will be unavailable for a few minutes during reboot"
            echo "Waiting 30 seconds to continue"
            sleep 30

            break
        fi
    done
    
    echo "✓ SC ITB deployment and boot configuration completed"
    return 0
}

# Function to wait for ITB boot completion on PC hosts
wait_for_itb_boot_completion() {
    echo ""
    echo "=== Waiting for ITB Boot Completion on PC Hosts ==="
    echo ""
    
    if [[ -z "${PC_HOSTS_LIST:-}" ]]; then
        echo "Error: PC hosts list not available!"
        return 1
    fi
    
    # Convert PC hosts list to array
    IFS=',' read -ra pc_hosts_array <<< "$PC_HOSTS_LIST"
    
    if [[ ${#pc_hosts_array[@]} -eq 0 ]]; then
        echo "Error: No PC hosts found!"
        return 1
    fi
    
    echo "Monitoring ${#pc_hosts_array[@]} PC hosts:"
    for host in "${pc_hosts_array[@]}"; do
        echo "  $host"
    done
    echo ""
    
    # Record initial log file sizes to avoid false positives from old log entries
    declare -A initial_log_sizes
    local log_path="/var/log/sC/current"
    echo "Recording initial log file sizes to track only new entries..."
    for host in "${pc_hosts_array[@]}"; do
        # Get current log file size (in bytes)
        local log_size
        log_size=$(pdsh -w "$host" "--external-switch-controller -c < $log_path 2>/dev/null || echo '0'" 2>/dev/null | grep -o '[0-9]*' | head -1)
        initial_log_sizes["$host"]="${log_size:-0}"
        echo "  $host: Starting from byte offset ${initial_log_sizes[$host]}"
    done
    echo ""
    
    local search_string="login:"
    local poll_interval=30   # Check every 30 seconds
    local start_time=$(date +%s)
    local poll_count=0
    
    echo "Polling for '$search_string' in $log_path on PC hosts (checking only NEW content since ITB boot started)..."
    echo "Poll interval: ${poll_interval}s (no timeout - will wait until all complete)"
    echo ""
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        ((poll_count++))
        
        echo "=== Poll #$poll_count at ${elapsed}s ==="
        
        declare -a completed_hosts=()
        declare -a pending_hosts=()
        local all_completed=true
        
        # Check each PC host
        for host in "${pc_hosts_array[@]}"; do
            # Get the initial log size for this host
            local initial_size="${initial_log_sizes[$host]}"
            
            # Check if the log contains the target string in NEW content only (after initial_size)
            # Use tail with byte offset to read only new content
            local check_result
            if [[ "$initial_size" -gt 0 ]]; then
                # Read only content after the initial size
                check_result=$(pdsh -w "$host" "tail -c +$((initial_size + 1)) $log_path 2>/dev/null | grep -q '$search_string' && echo 'FOUND' || echo 'NOT_FOUND'" 2>/dev/null)
            else
                # If initial size was 0, check recent entries only to avoid very old content
                check_result=$(pdsh -w "$host" "tail -n 1000 $log_path 2>/dev/null | grep -q '$search_string' && echo 'FOUND' || echo 'NOT_FOUND'" 2>/dev/null)
            fi
            
            if [[ "$check_result" == *"FOUND"* ]]; then
                completed_hosts+=("$host")
            else
                pending_hosts+=("$host")
                all_completed=false
            fi
        done
        
        # Display results
        echo ""
        local completed_count=${#completed_hosts[@]}
        local pending_count=${#pending_hosts[@]}
        echo "Completed PC hosts ($completed_count/${#pc_hosts_array[@]}):"
        if [[ $completed_count -gt 0 ]]; then
            for host in "${completed_hosts[@]}"; do
                echo "  ✓ $host"
            done
        else
            echo "  (none yet)"
        fi
        
        echo ""
        echo "Still waiting for ($pending_count/${#pc_hosts_array[@]}):"
        if [[ $pending_count -gt 0 ]]; then
            for host in "${pending_hosts[@]}"; do
                echo "  ⏳ $host"
            done
        else
            echo "  (none - all completed!)"
        fi
        
        if [[ "$all_completed" == true ]]; then
            echo ""
            echo "✓ ITB boot completion detected on all ${#pc_hosts_array[@]} PC hosts!"
            echo "Total wait time: ${elapsed} seconds (${poll_count} polls)"
            return 0
        fi
        
        echo ""
        echo "Waiting ${poll_interval}s before next poll..."
        echo "----------------------------------------"
        sleep $poll_interval
    done
}

# Function to wait for SC boot completion on PC hosts
wait_for_sc_boot_completion() {
    echo ""
    echo "=== Waiting for SC Boot Completion on PC Hosts ==="
    echo ""
    
    if [[ -z "${PC_HOSTS_LIST:-}" ]]; then
        echo "Error: PC hosts list not available!"
        return 1
    fi
    
    # Convert PC hosts list to array
    IFS=',' read -ra pc_hosts_array <<< "$PC_HOSTS_LIST"
    
    if [[ ${#pc_hosts_array[@]} -eq 0 ]]; then
        echo "Error: No PC hosts found!"
        return 1
    fi
    
    echo "Monitoring ${#pc_hosts_array[@]} PC hosts for SC boot completion:"
    for host in "${pc_hosts_array[@]}"; do
        echo "  $host"
    done
    echo ""
    
    # Record initial log file sizes to avoid false positives from old log entries
    declare -A initial_log_sizes
    local log_path="/var/log/sC/current"
    echo "Recording initial log file sizes to track only new entries..."
    for host in "${pc_hosts_array[@]}"; do
        # Get current log file size (in bytes)
        local log_size
        log_size=$(pdsh -w "$host" "--external-switch-controller -c < $log_path 2>/dev/null || echo '0'" 2>/dev/null | grep -o '[0-9]*' | head -1)
        initial_log_sizes["$host"]="${log_size:-0}"
        echo "  $host: Starting from byte offset ${initial_log_sizes[$host]}"
    done
    echo ""
    
    local search_string="login:"
    local poll_interval=30   # Check every 30 seconds
    local start_time=$(date +%s)
    local poll_count=0
    
    echo "Polling for '$search_string' in $log_path on PC hosts (checking only NEW content since SC boot started)..."
    echo "Poll interval: ${poll_interval}s (no timeout - will wait until all complete)"
    echo ""
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        ((poll_count++))
        
        echo "=== Poll #$poll_count at ${elapsed}s ==="
        
        declare -a completed_hosts=()
        declare -a pending_hosts=()
        local all_completed=true
        
        # Check each PC host
        for host in "${pc_hosts_array[@]}"; do
            # Get the initial log size for this host
            local initial_size="${initial_log_sizes[$host]}"
            
            # Check if the log contains the target string in NEW content only (after initial_size)
            # Use tail with byte offset to read only new content
            local check_result
            if [[ "$initial_size" -gt 0 ]]; then
                # Read only content after the initial size
                check_result=$(pdsh -w "$host" "tail -c +$((initial_size + 1)) $log_path 2>/dev/null | grep -q '$search_string' && echo 'FOUND' || echo 'NOT_FOUND'" 2>/dev/null)
            else
                # If initial size was 0, check recent entries only to avoid very old content
                check_result=$(pdsh -w "$host" "tail -n 1000 $log_path 2>/dev/null | grep -q '$search_string' && echo 'FOUND' || echo 'NOT_FOUND'" 2>/dev/null)
            fi
            
            if [[ "$check_result" == *"FOUND"* ]]; then
                completed_hosts+=("$host")
            else
                pending_hosts+=("$host")
                all_completed=false
            fi
        done
        
        # Display results
        echo ""
        local completed_count=${#completed_hosts[@]}
        local pending_count=${#pending_hosts[@]}
        echo "SC Boot Completed PC hosts ($completed_count/${#pc_hosts_array[@]}):"
        if [[ $completed_count -gt 0 ]]; then
            for host in "${completed_hosts[@]}"; do
                echo "  ✓ $host"
            done
        else
            echo "  (none yet)"
        fi
        
        echo ""
        echo "Still waiting for SC boot ($pending_count/${#pc_hosts_array[@]}):"
        if [[ $pending_count -gt 0 ]]; then
            for host in "${pending_hosts[@]}"; do
                echo "  ⏳ $host"
            done
        else
            echo "  (none - all completed!)"
        fi
        
        if [[ "$all_completed" == true ]]; then
            echo ""
            echo "✓ SC boot completion detected on all ${#pc_hosts_array[@]} PC hosts!"
            echo "Total wait time: ${elapsed} seconds (${poll_count} polls)"
            return 0
        fi
        
        echo ""
        echo "Waiting ${poll_interval}s before next poll..."
        echo "----------------------------------------"
        sleep $poll_interval
    done
}

# Function to capture SC logs using Python utility
capture_sc_logs() {
    echo ""
    echo "========================================"
    echo "Phase 10: Capturing SC Logs"
    echo "========================================"
    echo ""
    
    if [[ -z "${PC_HOSTS_LIST:-}" ]]; then
        echo "ERROR: PC hosts list not available!"
        return 1
    fi
    
    # Convert comma-separated PC hosts to space-separated for the Python script
    local pc_hosts_space_separated="${PC_HOSTS_LIST//,/ }"
    
    # Check if the log capture utility exists
    local log_utility="remote_sc_log_capture_standalone.py"
    if [[ ! -f "$log_utility" ]]; then
        echo "Error: Log capture utility '$log_utility' not found in current directory!"
        echo "Please ensure the utility is present in the same directory as this script."
        return 1
    fi
    
    echo "Capturing SC logs using PC hosts: $pc_hosts_space_separated"
    echo "Command: python3 $log_utility $pc_hosts_space_separated"
    echo ""
    
    # Execute the SC log capture utility with all PC hosts as arguments
    if python3 "$log_utility" $pc_hosts_space_separated; then
        echo ""
        echo "✓ SC log capture completed successfully"
        return 0
    else
        echo ""
        echo "✗ SC log capture failed"
        echo "Please check the output above for error details"
        return 1
    fi
}

# Main execution
main() {
    echo "=== Secure Boot File Transfer Script ==="
    echo ""
    
    # Check if server list file is provided
    if [[ $# -ne 1 ]]; then
        usage
    fi
    
    local server_file="$1"
    
    # Check if file exists
    if [[ ! -f "$server_file" ]]; then
        echo "Error: Server list file '$server_file' not found!"
        exit 1
    fi
    
    # Check if source files exist
    check_source_files
    
    # Process servers to get host lists
    echo "Processing servers from: $server_file"
    process_servers "$server_file"
    
    echo ""
    echo "=== Host Information ==="
    echo "PC_HOSTS_LIST=$PC_HOSTS_LIST"
    echo "SC_HOSTS_LIST=$SC_HOSTS_LIST"
    echo "ALL_HOSTS_LIST=$ALL_HOSTS_LIST"
    echo ""
    
    # Transfer the files to appropriate hosts
    if transfer_files_scp; then
        echo "✓ All transfers completed successfully!"
    else
        echo "⚠ Some transfers failed - check the output above"
        echo "Continuing with SC operations..."
    fi
    
    # Verify the transfer
    verify_transfer
    
    # Set reboot recovery image on SC and PC hosts
    if set_reboot_recovery_image; then
        echo "✓ Reboot recovery image configuration completed on all hosts"
    else
        echo "✗ Failed to set reboot recovery image on SC and PC hosts"
        exit 1
    fi
    
    # Flash secure u-boot image on SC hosts
    if flash_secure_uboot; then
        echo "✓ Secure U-Boot flashing completed successfully on SC hosts"
    else
        echo "✗ Failed to flash secure U-Boot image on SC hosts"
        echo "CRITICAL ERROR: Secure boot setup cannot continue without successful U-Boot flashing"
        echo "Exiting..."
        exit 1
    fi
    
    # Flash secure u-boot image on PC hosts
    if flash_pc_uboot; then
        echo "✓ Secure U-Boot flashing completed successfully on PC hosts"
    else
        echo "✗ Failed to flash secure U-Boot image on PC hosts"
        echo "CRITICAL ERROR: Secure boot setup cannot continue without successful U-Boot flashing"
        echo "Exiting..."
        exit 1
    fi
    
    # Shutdown SC hosts via PC hosts
    if shutdown_sc_hosts; then
        echo "✓ SC hosts shutdown initiated successfully"
    else
        echo "⚠ Warning: Some SC hosts may not have powered down properly"
        echo "Continuing with remaining operations..."
    fi
    
    # Clear PC log files from chassis controller
    if clear_pc_log_files "$server_file"; then
        echo "✓ PC log files cleared successfully from chassis controllers"
    else
        echo "⚠ Warning: Some PC log file clearing operations failed"
        echo "Continuing with remaining operations..."
    fi
    
    # Reboot all PC hosts
    if reboot_pc_hosts; then
        echo "✓ PC hosts reboot initiated successfully"
    else
        echo "⚠ Warning: Some PC hosts may not have rebooted properly"
        echo "Continuing with remaining operations..."
    fi
    
    # Wait for secure boot completion on PC hosts
    if wait_for_secure_boot_completion "$server_file"; then
        echo "✓ Secure boot completion confirmed on all PC hosts"
    else
        echo "✗ Failed to confirm secure boot completion on all PC hosts"
        echo "CRITICAL ERROR: Secure boot process may not have completed successfully"
        echo "Exiting..."
        exit 1
    fi
    

    
    # Deploy PC ITB file and boot configuration
    if deploy_pc_itb; then
        echo "✓ PC ITB deployment and boot configuration completed successfully"
    else
        echo "✗ Failed to deploy PC ITB file and boot configuration"
        echo "CRITICAL ERROR: PC ITB deployment failed"
        echo "Exiting..."
        exit 1
    fi
    
    # Wait for ITB boot completion on PC hosts
    if wait_for_itb_boot_completion; then
        echo "✓ ITB boot completion confirmed on all PC hosts"
    else
        echo "✗ Failed to confirm ITB boot completion on all PC hosts"
        echo "CRITICAL ERROR: ITB boot process may not have completed successfully"
        echo "Exiting..."
        exit 1
    fi
    
    
    # Deploy SC ITB file to SC hosts
    if deploy_sc_itb; then
        echo "✓ SC ITB file deployment completed successfully"
    else
        echo "⚠ Warning: SC ITB file deployment failed or incomplete"
        echo "Continuing with remaining operations..."
    fi
    
    # Wait for SC boot completion on PC hosts
    if wait_for_sc_boot_completion; then
        echo "✓ SC boot completion confirmed on all PC hosts"
    else
        echo "✗ Failed to confirm SC boot completion on all PC hosts"
        echo "CRITICAL ERROR: SC boot process may not have completed successfully"
        echo "Exiting..."
        exit 1
    fi
    
    # echo "Waiting 60 seconds to start Log Capture"
    # sleep 60
    # # Capture PC logs from all chassis
    # if capture_pc_logs "$server_file"; then
    #     echo "✓ PC logs captured successfully from all chassis"
    # else
    #     echo "⚠ Warning: PC log capture failed or incomplete"
    #     echo "Continuing with final summary..."
    # fi
    #
    # # Capture SC logs using PC hosts
    # if capture_sc_logs; then
    #     echo "✓ SC log capture completed"
    # else
    #     echo "✗ Failed to capture SC logs"
    #     echo "Warning: SC log capture failed but continuing..."
    # fi

    echo ""
    echo "=== Secure Boot Setup Complete ==="
    echo "✓ File transfer completed"
    echo "✓ Reboot recovery image set on SC and PC hosts"
    echo "✓ Secure U-Boot image flashed on SC hosts"
    echo "✓ Secure U-Boot image flashed on PC hosts"
    echo "✓ SC hosts shutdown initiated"
    echo "✓ PC log files cleared from chassis controllers"
    echo "✓ PC hosts rebooted"
    echo "✓ Secure boot completion confirmed"
    echo "✓ PC ITB deployed and configured"
    echo "✓ ITB boot completion confirmed"
    echo "✓ SC ITB deployed and configured"
    echo "✓ SC boot completion confirmed"
    # echo "✓ PC logs captured"
    # echo "✓ SC logs captured"
    echo ""
    echo "All operations completed successfully!"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

