#!/bin/bash

set -x

source ./cbdctrl.py.data/cbdctrl_utils.sh

prepare

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

cbdctrl_tp_unreg $blkdev_node 0 "false"
if $multihost_mode; then
	cbdctrl_tp_unreg $backend_node 0 "false"
fi
