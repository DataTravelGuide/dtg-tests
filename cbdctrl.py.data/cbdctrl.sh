#!/bin/bash

set -x

# Cleanup function to run on script exit
cleanup() {
	echo "Running cleanup..."
	ssh "$blkdev_node" cbdctrl dev-stop --dev 0
	ssh "$blkdev_node" cbdctrl dev-stop --dev 1
	ssh "$backend_node" cbdctrl backend-stop --backend 0
	ssh "$backend_node" cbdctrl backend-stop --backend 1
	ssh "$backend_node" cbdctrl tp-unreg --transport 0
	if [[ "$blkdev_node" != "$backend_node" ]]; then
		ssh "$blkdev_node" cbdctrl tp-unreg --transport 0
	fi
}

# Set trap to call cleanup on EXIT
trap cleanup EXIT

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
	local node="$1"
	local host="$2"
	local path="$3"
	local format="$4"
	local force="$5"
	local expect_fail="$6"

	cmd="cbdctrl tp-reg"
	[[ -n "$host" ]] && cmd+=" --host $host"
	[[ -n "$path" ]] && cmd+=" -p $path"
	[[ "$format" == "true" ]] && cmd+=" --format"
	[[ "$force" == "true" ]] && cmd+=" --force"

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

	cmd="cbdctrl backend-start"
	[[ -n "$transport_id" ]] && cmd+=" --transport $transport_id"
	[[ -n "$path" ]] && cmd+=" --path $path"
	[[ -n "$cache_size" ]] && cmd+=" --cache-size $cache_size"
	[[ -n "$handlers" ]] && cmd+=" --handlers $handlers"
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
	host=$1  # ${blkdev_node} 的主机名或IP
	port=${2:-22}  # SSH端口，默认为22
	user=${3:-root}  # SSH登录用户名，默认为root
	max_attempts=${4:-30}  # 最大重试次数，默认30次
	wait_time=${5:-5}  # 每次尝试之间等待时间，默认5秒

	timeout -s 9 20 ssh -o ControlMaster=no -p "$port" "$user@$host" 'exit' 2>/dev/null
}

wait_for_qemu_ssh() {
    local host=$1  # ${backend_node} 的主机名或IP
    local port=${2:-22}  # SSH端口，默认为22
    local user=${3:-root}  # SSH登录用户名，默认为root
    local max_attempts=${4:-30}  # 最大重试次数，默认30次
    local wait_time=${5:-5}  # 每次尝试之间等待时间，默认5秒

    echo "Waiting for ${backend_node} to become available via SSH..."

    attempt=0
    while (( attempt < max_attempts )); do
        # 尝试使用SSH无密码连接到${backend_node}，返回状态码
	check_ssh $@
        ssh_status=$?

        if [ $ssh_status -eq 0 ]; then
            echo "${backend_node} is up and SSH is available!"
            return 0
        else
            echo "Attempt $((++attempt))/$max_attempts failed (exit code $ssh_status), retrying in $wait_time seconds..."
            sleep "$wait_time"
        fi
    done

    echo "${backend_node} is not reachable after $max_attempts attempts."
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

env

ssh ${blkdev_node} "rmmod cbd; insmod /workspace/linux_compile/drivers/block/cbd/cbd.ko"
ssh ${backend_node} "rmmod cbd; insmod /workspace/linux_compile/drivers/block/cbd/cbd.ko"

if [[ "$backend_node" == "$blkdev_node" ]]; then
    multihost_mode=false
else
    multihost_mode=true
fi

# cbdctrl tp-reg and cbdctrl tp-unreg testing
cbdctrl_tp_reg $blkdev_node "node1" "/dev/pmem0" "true" "true" "false"
transport_path=`ssh $blkdev_node "cat /sys/bus/cbd/devices/transport0/path"`
if [[ "$transport_path" != "/dev/pmem0" ]]; then
	echo "path of transport is not expected"
	exit 1
fi
cbdctrl_tp_unreg $blkdev_node 0 "false"

cbdctrl_tp_reg $blkdev_node "node1" "/dev/pmem0" "true" "false" "true"
cbdctrl_tp_reg $blkdev_node "" "/dev/pmem0" "true" "true" "true"
cbdctrl_tp_reg $blkdev_node "node1" "" "true" "true" "true"

cbdctrl_tp_reg $blkdev_node "node1" "/dev/pmem0" "false" "false" "false"
if $multihost_mode; then
	cbdctrl_tp_reg $backend_node "node2" "/dev/pmem0" "false" "false" "false"
fi

# cbdctrl backend-start and cbdctrl backend-stop testing
cbdctrl_backend_start $backend_node 0 $backend_blk "" "" true "0"

cbdctrl_backend_start $backend_node 0 $backend_blk "" "" false
cbdctrl_backend_start $backend_node 0 $backend_blk "" "" true # device busy

if $multihost_mode; then
	kill_qemu_2
	wait_for_qemu_ssh "${backend_node}" 22 "root" 100 5
	ssh ${backend_node} "rmmod cbd; insmod /workspace/linux_compile/drivers/block/cbd/cbd.ko"
	cbdctrl_tp_reg $backend_node "node2" "/dev/pmem0" "false" "false" "false"

	run_remote_cmd $backend_node "echo 'op=backend-start,path=${backend_blk},backend_id=10' > /sys/bus/cbd/devices/transport0/adm"

	if [[ $? -eq 0 ]]; then
		echo "Error: Command succeeded unexpectedly."
		exit 1
	fi
	cbdctrl_backend_start $backend_node 0 $backend_blk "" "" false
fi


cbdctrl_dev_start $blkdev_node 0 0 "false"
cbdctrl_dev_start $blkdev_node 0 0 "true" # backend busy
cbdctrl_dev_stop $blkdev_node 0 0  false
cbdctrl_dev_stop $blkdev_node 0 0  true # blkdev stopped
cbdctrl_backend_stop $backend_node 0 0 false
cbdctrl_backend_stop $backend_node 0 0 true # backend stopped

cbdctrl_backend_start $backend_node 0 $backend_blk "200M" 1 false # cache backend
cbdctrl_dev_start $blkdev_node 0 0 "false"
cbdctrl_dev_stop $blkdev_node 0 0  false
cbdctrl_backend_stop $backend_node 0 0 false

cbdctrl_backend_start $backend_node 1 $backend_blk "200M" 1 true # invalid transport id
cbdctrl_backend_start $backend_node 0 $backend_blk "1M" 1 true # invalid cache-size
cbdctrl_backend_start $backend_node 0 $backend_blk "200M" 129 true # invalid handlers too large
cbdctrl_backend_start $backend_node 0 $backend_blk "200M" 0 true # invalid handlers too small

cbdctrl_backend_start $backend_node 0 /dev/NOTFOUND "" "" true # not found device
cbdctrl_backend_start $backend_node 0 INVALID "" "" true # invalid path
cbdctrl_backend_start $backend_node 0 $backend_blk "512G" 1 true # too large cache-size

if [[ "${cache_for_xfstests}" == "true" ]]; then
	cbdctrl_backend_start $backend_node 0 $backend_blk "1G" 1 false
	cbdctrl_backend_start $backend_node 0 $backend_blk_2 "1G" 1 false
else
	cbdctrl_backend_start $backend_node 0 $backend_blk "" 1 false
	cbdctrl_backend_start $backend_node 0 $backend_blk_2 "" 1 false
fi

cbdctrl_dev_start $blkdev_node 1 0 true # invalid transport_id
cbdctrl_dev_start $blkdev_node 0 100 true # invalid backend id
cbdctrl_dev_start $blkdev_node 0 0 false
cbdctrl_dev_start $blkdev_node 0 1 false
run_remote_cmd $blkdev_node "mkfs.xfs -f /dev/cbd0"

if $multihost_mode; then
	monitor_qemu &
	monitor_pid=$!

	# Start the function in the background
	kill_qemu_2_loop &
	# Save the process ID of the background task so we can stop it later
	kill_qemu_pid=$!
fi

run_remote_cmd $blkdev_node "/root/run_xfstests.sh"

if $multihost_mode; then
	kill $kill_qemu_pid
	wait $kill_qemu_pid

	kill $monitor_pid
	wait $monitor_pid

	wait_for_qemu_ssh "${backend_node}" 22 "root" 100 5
	cbdctrl_tp_reg $backend_node "node2" "/dev/pmem0" "false" "false" "ignore"
	cbdctrl_backend_start $backend_node 0 $backend_blk "" 1 ignore
	cbdctrl_backend_start $backend_node 0 $backend_blk_2 "" 1 ignore
fi

cbdctrl_dev_stop $blkdev_node 0 0 false
cbdctrl_dev_stop $blkdev_node 0 1 false

cbdctrl_tp_unreg $backend_node 0 true # backend busy 

cbdctrl_backend_stop $backend_node 0 0
cbdctrl_backend_stop $backend_node 0 1

cbdctrl_tp_unreg $blkdev_node 0 "false"
if $multihost_mode; then
	cbdctrl_tp_unreg $backend_node 0 "false"
fi
# Print PASS if the command was successful
echo "PASS"
