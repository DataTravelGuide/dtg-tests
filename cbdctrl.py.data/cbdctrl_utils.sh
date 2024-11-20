#!/bin/bash

# Cleanup function to run on script exit
cleanup() {
	echo "Running cleanup..."
	ssh "$blkdev_node" cbdctrl dev-stop --dev 0
	ssh "$blkdev_node" cbdctrl dev-stop --dev 1
	ssh "$backend_node" cbdctrl dev-stop --dev 0
	ssh "$backend_node" cbdctrl dev-stop --dev 1
	ssh "$backend_node" cbdctrl backend-stop --backend 0
	ssh "$backend_node" cbdctrl backend-stop --backend 1
	ssh "$backend_node" cbdctrl tp-unreg --transport 0
	if [[ "$blkdev_node" != "$backend_node" ]]; then
		ssh "$blkdev_node" cbdctrl tp-unreg --transport 0
	fi
}

run_remote_cmd() {
    local node="$1"
    local cmd="$2"

    if [[ -z "$node" || -z "$cmd" ]]; then
        echo "Error: Node and command cannot be empty."
        return 1
    fi

    ssh "$node" "$cmd"
    local status=$?

    if [[ $status -ne 0 ]]; then
        echo "Error: Command failed with status $status"
        return $status
    fi
}

# Register a transport on the specified backend node
cbdctrl_tp_reg() {
    local node="$1"       # Remote node where the command will be executed
    local host="$2"       # Hostname for the transport
    local path="$3"       # Backend path to be used
    local format="$4"     # Whether to format the transport (true/false)
    local force="$5"      # Whether to force the operation (true/false)
    local expect_fail="$6" # Whether failure is expected ("true", "false", or "ignore")

    # Construct the cbdctrl tp-reg command
    cmd="cbdctrl tp-reg"
    [[ -n "$host" ]] && cmd+=" --host $host"
    [[ -n "$path" ]] && cmd+=" -p $path"
    [[ "$format" == "true" ]] && cmd+=" --format"
    [[ "$force" == "true" ]] && cmd+=" --force"

    # Execute the registration command on the remote node
    run_remote_cmd "$node" "$cmd"
    local result=$?

    # If failure is to be ignored, return immediately
    if [[ "$expect_fail" == "ignore" ]]; then
        return
    fi

    # Validate command result against expectations
    if [[ "$expect_fail" == "true" && $result -eq 0 ]]; then
        echo "Error: Command succeeded unexpectedly."
        exit 1
    elif [[ "$expect_fail" != "true" && $result -ne 0 ]]; then
        echo "Error: Command failed unexpectedly with return code $result."
        exit 1
    fi

    # Skip further checks if failure is expected
    if [[ "$expect_fail" == "true" ]]; then
        return
    fi

    # Fetch the transport list to verify the registration
    local tp_list_output
    tp_list_output=$(run_remote_cmd "$node" "cbdctrl tp-list")
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to fetch tp-list from $node."
        exit 1
    fi

    # Parse JSON output to validate the path
    local actual_path
    actual_path=$(echo "$tp_list_output" | jq -r '.[] | select(.path == "'"$path"'") | .path')
    if [[ "$actual_path" != "$path" ]]; then
        echo "Error: Path in tp-list ($actual_path) does not match expected path ($path)."
        exit 1
    fi

    echo "Transport registered successfully with expected path: $path"
}

# Unregister a transport on the specified backend node
cbdctrl_tp_unreg() {
	local node="$1"
	local transport_id="$2"
	local expect_fail="$3"

	cmd="cbdctrl tp-unreg"
	[[ -n "$transport_id" ]] && cmd+=" --transport $transport_id"

	run_remote_cmd "$node" "$cmd" 
	local result=$?

	if [[ "$expect_fail" == "ignore" ]]; then
		return
	fi

	if [[ "$expect_fail" == "true" && $result -eq 0 ]]; then
		echo "Error: Command succeeded unexpectedly."
		exit 1
	elif [[ "$expect_fail" != "true" && $result -ne 0 ]]; then
		echo "Error: Command failed unexpectedly with return code $result."
		exit 1
	fi
}

# Start a backend on the specified backend node
cbdctrl_backend_start() {
	local node="$1"
	local transport_id="$2"
	local path="$3"
	local cache_size="$4"
	local handlers="$5"
	local expect_fail="$6"
	local backend_id="$7"
	local start_dev="$8"

	cmd="cbdctrl backend-start"
	[[ -n "$transport_id" ]] && cmd+=" --transport $transport_id"
	[[ -n "$path" ]] && cmd+=" --path $path"
	[[ -n "$cache_size" ]] && cmd+=" --cache-size $cache_size"
	[[ -n "$handlers" ]] && cmd+=" --handlers $handlers"
	[[ -n "$backend_id" ]] && cmd+=" --backend $backend_id"
	[[ -n "$start_dev" ]] && cmd+=" --start-dev"

	local startoutput
	start_output=$(run_remote_cmd "$node" "$cmd")
	local result=$?

	if [[ "$expect_fail" == "ignore" ]]; then
		return
	fi

	if [[ "$expect_fail" == "true" && $result -eq 0 ]]; then
		echo "Error: Command succeeded unexpectedly."
		exit 1
	elif [[ "$expect_fail" != "true" && $result -ne 0 ]]; then
		echo "Error: Command failed unexpectedly with return code $result."
		exit 1
	fi

	# Validate output format if start_dev is set and expect_fail is false
	if [[ -n "$start_dev" && "$expect_fail" != "true" ]]; then
		if [[ ! "$start_output" =~ ^/dev/cbd[0-9]+$ ]]; then
			echo "Error: Unexpected output format. Expected /dev/cbdX, but got: $start_output"
			exit 1
		fi
	fi
}

# Stop a backend on the specified backend node
cbdctrl_backend_stop() {
	local node="$1"
	local transport_id="$2"
	local backend_id="$3"
	local expect_fail="$4"

	cmd="cbdctrl backend-stop"
	[[ -n "$transport_id" ]] && cmd+=" --transport $transport_id"
	[[ -n "$backend_id" ]] && cmd+=" --backend $backend_id"

	run_remote_cmd "$node" "$cmd" 
	local result=$?

	if [[ "$expect_fail" == "ignore" ]]; then
		return
	fi

	if [[ "$expect_fail" == "true" && $result -eq 0 ]]; then
		echo "Error: Command succeeded unexpectedly."
		exit 1
	elif [[ "$expect_fail" != "true" && $result -ne 0 ]]; then
		echo "Error: Command failed unexpectedly with return code $result."
		exit 1
	fi
}

# Start a device on the specified block device node
cbdctrl_dev_start() {
	local node="$1"
	local transport_id="$2"
	local backend_id="$3"
	local expect_fail="$4"

	cmd="cbdctrl dev-start"
	[[ -n "$transport_id" ]] && cmd+=" --transport $transport_id"
	[[ -n "$backend_id" ]] && cmd+=" --backend $backend_id"

	run_remote_cmd "$node" "$cmd" 
	local result=$?

	if [[ "$expect_fail" == "ignore" ]]; then
		return
	fi

	if [[ "$expect_fail" == "true" && $result -eq 0 ]]; then
		echo "Error: Command succeeded unexpectedly."
		exit 1
	elif [[ "$expect_fail" != "true" && $result -ne 0 ]]; then
		echo "Error: Command failed unexpectedly with return code $result."
		exit 1
	fi
}

# Stop a device on the specified block device node
cbdctrl_dev_stop() {
	local node="$1"
	local transport_id="$2"
	local dev_id="$3"
	local expect_fail="$4"
	local max_retries=1
	local retry_interval=1
	local attempt=0
	local result=1

	cmd="cbdctrl dev-stop"
	[[ -n "$transport_id" ]] && cmd+=" --transport $transport_id"
	[[ -n "$dev_id" ]] && cmd+=" --dev $dev_id"

	while [[ $attempt -lt $max_retries ]]; do
		run_remote_cmd "$node" "$cmd" 
		result=$?

		if [[ "$expect_fail" == "ignore" ]]; then
			return
		fi

		if [[ "$expect_fail" == "true" && $result -ne 0 ]]; then
			return 0
		elif [[ "$expect_fail" != "true" && $result -eq 0 ]]; then
			return 0
		fi

		((attempt++))
		echo "Attempt $attempt/$max_retries failed, retrying in $retry_interval second(s)..."
		sleep "$retry_interval"
	done

	echo "Error: Command failed unexpectedly after $max_retries attempts."
	exit 1
}

function kill_qemu_2() {
        ps -ef | grep qemu-system | grep jammy-server-cloudimg-amd64_2.raw | gawk '{print "kill -9 "$2}' | bash
}

# Function that will execute the command in a loop
function kill_qemu_2_loop() {
    while true ; do
        # Wait for a random interval between 100 and 300 seconds
        #sleep_time=$((100 + RANDOM % 201))
	sleep_time=100
        echo "Waiting $sleep_time seconds before executing command..."
        sleep $sleep_time

        # Execute the command
	kill_qemu_2
        echo "Command executed once"
    done
    echo "Background loop stopped"
}


# Function to wait until ${backend_node} has stopped
function wait_qemu_2_stopped() {
    local qemu_ip="${backend_node}"    # Replace with the IP address of ${backend_node}
    local interval=5           # Time in seconds between each check
    local fail_count=0         # Counter for consecutive ping failures
    local fail_threshold=1     # Number of consecutive failures to consider stopped

    echo "Waiting for ${backend_node} at $qemu_ip to shut down..."

    while true; do
        # Ping once and check if it fails
        if ! ping -c 1 "$qemu_ip" &> /dev/null; then
            ((fail_count++))
            echo "Ping failed ($fail_count/$fail_threshold)"
        else
            # Reset fail count if a ping is successful
            fail_count=0
        fi

        # Check if failure threshold is reached
        if [[ $fail_count -ge $fail_threshold ]]; then
            echo "${backend_node} has shut down and is no longer reachable."
            break
        fi

        # Wait before the next check
        sleep "$interval"
    done
}

check_ssh() {
	local host=$1  # Hostname or IP of the target machine (e.g., blkdev_node)
	local port=${2:-22}  # SSH port, defaults to 22
	local user=${3:-root}  # SSH username, defaults to root

	# Attempt to connect to the host using SSH with a timeout of 20 seconds.
	# -o BatchMode=yes: Ensures non-interactive mode (no password prompts).
	# -o ConnectTimeout=5: Sets a timeout for the SSH connection attempt.
	timeout 20s ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$port" "$user@$host" 'exit' 2>/dev/null
	return $?  # Return the exit status of the SSH command
}

wait_for_qemu_ssh() {
	local host=$1  # Hostname or IP of the target machine (e.g., backend_node)
	local port=${2:-22}  # SSH port, defaults to 22
	local user=${3:-root}  # SSH username, defaults to root
	local max_attempts=${4:-30}  # Maximum number of retry attempts, defaults to 30
	local wait_time=${5:-5}  # Time to wait between retries, defaults to 5 seconds

	echo "Waiting for $host to become available via SSH..."

	local attempt=0
	while (( attempt < max_attempts )); do
		# Call check_ssh to verify if SSH is accessible
		check_ssh "$host" "$port" "$user"
		local ssh_status=$?

		if [ $ssh_status -eq 0 ]; then
			echo "$host is up and SSH is available!"
			return 0  # SSH is accessible
		else
			# Increment the attempt counter and wait before retrying
			echo "Attempt $((++attempt))/$max_attempts failed (exit code $ssh_status), retrying in $wait_time seconds..."
			sleep "$wait_time"
		fi
	done

	# If all attempts fail, print an error message and return a failure status
	echo "$host is not reachable after $max_attempts attempts."
	return 1
}

function monitor_qemu() {
    while true; do
        # Wait for ${backend_node} to stop
        wait_qemu_2_stopped

        # After ${backend_node} stopped, wait for SSH to become available
        wait_for_qemu_ssh "${backend_node}" 22 "root" 100 5

        # Perform additional operations (example: sleep for 1 second)
        echo "${backend_node} has restarted."

	ssh ${backend_node} "rmmod cbd; insmod /workspace/linux_compile/drivers/block/cbd/cbd.ko"
	cbdctrl_tp_reg $backend_node "node2" "/dev/pmem0" "false" "false" "ignore"
	cbdctrl_backend_start $backend_node 0 $backend_blk "" 1 ignore
	cbdctrl_backend_start $backend_node 0 $backend_blk_2 "" 1 ignore
    done
}

function prepare() {
	# Set trap to call cleanup on EXIT
	trap cleanup EXIT

	env
	cd ${kernel_dir}

	# List of variable names to check
	for var in ${config_list} ; do
	    # Check if the variable is set and whether it's true or false
	    if [ "${!var}" == "true" ]; then
		./scripts/config --enable "$var"
	    elif [ "${!var}" == "false" ]; then
		./scripts/config --disable "$var"
	    else
		echo "Warning: $var is ${!var} not set to 'true' or 'false'"
	    fi
	done

	cat .config|grep CBD_

	make prepare; make -j 42 M=drivers/block/cbd/
	if [[ $? != 0 ]]; then
		exit 1
	fi

	ssh ${blkdev_node} "rmmod cbd; insmod /workspace/linux_compile/drivers/block/cbd/cbd.ko"
	ssh ${backend_node} "rmmod cbd; insmod /workspace/linux_compile/drivers/block/cbd/cbd.ko"

	if [[ "$backend_node" == "$blkdev_node" ]]; then
	    multihost_mode=false
	else
	    multihost_mode=true
	fi
}
