#!/bin/bash

set -x

source ./cbdctrl.py.data/cbdctrl_utils.sh

prepare

# cbdctrl tp-reg and cbdctrl tp-unreg testing
run_remote_cmd $blkdev_node "echo 'path=/dev/pmem0,hostname=\"node-1\",hostid=1024' > /sys/bus/cbd/transport_register"

if [[ $? -eq 0 ]]; then
	echo "Error: Command succeeded unexpectedly."
	exit 1
fi

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
	if [[ ${CBD_MULTIHOST} == "true" ]]; then
		cbdctrl_tp_reg $backend_node "node2" "/dev/pmem0" "false" "false" "false"
	else
		cbdctrl_tp_reg $backend_node "node2" "/dev/pmem0" "false" "false" "true"
		exit 0
	fi
fi

# cbdctrl backend-start and cbdctrl backend-stop testing
cbdctrl_backend_start $backend_node 0 $backend_blk "" "" true "0"

cbdctrl_backend_start $backend_node 0 $backend_blk "" "" false
cbdctrl_backend_start $backend_node 0 $backend_blk "" "" true # device busy

if $multihost_mode; then
	kill_qemu_2
	wait_for_qemu_ssh "${backend_node}" 22 "root" 20 5
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

run_remote_cmd $blkdev_node "cd /root/xfstests/;./check generic/001"
if [[ $? != 0 ]]; then
	exit 1
fi

if $multihost_mode; then
	kill $kill_qemu_pid
	wait $kill_qemu_pid

	kill $monitor_pid
	wait $monitor_pid

	wait_for_qemu_ssh "${backend_node}" 22 "root" 20 5
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
exit 0
