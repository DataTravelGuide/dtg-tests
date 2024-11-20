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

cbdctrl_backend_start $backend_node 0 $backend_blk "" 1 false
cbdctrl_backend_start $backend_node 0 $backend_blk_2 "" 1 false

cbdctrl_dev_start $blkdev_node 1 0 true # invalid transport_id
cbdctrl_dev_start $blkdev_node 0 100 true # invalid backend id
cbdctrl_dev_start $blkdev_node 0 0 false
cbdctrl_dev_start $blkdev_node 0 1 false
run_remote_cmd $blkdev_node "mkfs.xfs -f /dev/cbd0; mount /dev/cbd0 /media; dd if=/dev/urandom of=/root/100M bs=1M count=100 oflag=direct; dd if=/root/100M of=/media/100M bs=1M count=100 oflag=direct; sync"

expected_md5=$(run_remote_cmd ${blkdev_node} "md5sum /root/100M" | awk '{print $1}')
real_md5=$(run_remote_cmd ${blkdev_node} "md5sum /media/100M" | awk '{print $1}')

echo "expected: $expected_md5 real: $real_md5 "

if $multihost_mode; then
	kill_blkdev_node
        wait_for_qemu_ssh "${blkdev_node}" 22 "root" 100 5
	ssh ${blkdev_node} "rmmod cbd; insmod /workspace/linux_compile/drivers/block/cbd/cbd.ko"
	cbdctrl_tp_reg $blkdev_node "node1" "/dev/pmem0" "false" "false" "false"
	cbdctrl_dev_start $blkdev_node 0 0 false
	cbdctrl_dev_start $blkdev_node 0 1 false
	run_remote_cmd $blkdev_node "mount /dev/cbd0 /media"

	# Extract only the MD5 checksum part using awk
	expected_md5=$(run_remote_cmd ${blkdev_node} "md5sum /root/100M" | awk '{print $1}')
	real_md5=$(run_remote_cmd ${blkdev_node} "md5sum /media/100M" | awk '{print $1}')

	run_remote_cmd $blkdev_node "umount /media"

	# Compare only the MD5 values
	if [[ "$expected_md5" != "$real_md5" ]]; then
			echo "Error: expected_md5: $expected_md5, real_md5: $real_md5"
				exit 1
	fi
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
