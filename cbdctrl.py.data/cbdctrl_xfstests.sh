#!/bin/bash

set -x

source ./cbdctrl.py.data/cbdctrl_utils.sh

prepare

cbdctrl_tp_reg $blkdev_node "node1" "/dev/pmem0" "true" "true" "false"
if $multihost_mode; then
	if [[ ${CBD_MULTIHOST} == "true" ]]; then
		cbdctrl_tp_reg $backend_node "node2" "/dev/pmem0" "false" "false" "false"
	else
		cbdctrl_tp_reg $backend_node "node2" "/dev/pmem0" "false" "false" "true"
		exit 0
	fi
fi

if [[ "${cache_for_xfstests}" == "true" ]]; then
	cbdctrl_backend_start $backend_node 0 $backend_blk "1G" 1 false
	cbdctrl_backend_start $backend_node 0 $backend_blk_2 "1G" 1 false
else
	cbdctrl_backend_start $backend_node 0 $backend_blk "" 1 false
	cbdctrl_backend_start $backend_node 0 $backend_blk_2 "" 1 false
fi

cbdctrl_dev_start $blkdev_node 0 0 false
cbdctrl_dev_start $blkdev_node 0 1 false
run_remote_cmd $blkdev_node "mkfs.xfs -f /dev/cbd0"

if $multihost_mode; then
	echo "multihost_mode kill backend node\n"
	monitor_qemu &
	monitor_pid=$!

	# Start the function in the background
	kill_backend_node_loop &
	# Save the process ID of the background task so we can stop it later
	kill_qemu_pid=$!
fi

run_remote_cmd $blkdev_node "cd /root/xfstests/;./check generic/031"
if [[ $? != 0 ]]; then
	exit 1
fi

if $multihost_mode; then
	kill $kill_qemu_pid
	wait $kill_qemu_pid

	kill $monitor_pid
	wait $monitor_pid

	wait_for_qemu_ssh "${backend_node}" 22 "root" 100 5
	ssh ${backend_node} "rmmod cbd; insmod /workspace/linux_compile/drivers/block/cbd/cbd.ko"
	cbdctrl_tp_reg $backend_node "node2" "/dev/pmem0" "false" "false" "ignore"
	cbdctrl_backend_start $backend_node 0 $backend_blk "" 1 ignore
	cbdctrl_backend_start $backend_node 0 $backend_blk_2 "" 1 ignore
fi

cbdctrl_dev_stop $blkdev_node 0 0 false
cbdctrl_dev_stop $blkdev_node 0 1 false

cbdctrl_backend_stop $backend_node 0 0
cbdctrl_backend_stop $backend_node 0 1

cbdctrl_tp_unreg $blkdev_node 0 "false"
if $multihost_mode; then
	cbdctrl_tp_unreg $backend_node 0 "false"
fi
