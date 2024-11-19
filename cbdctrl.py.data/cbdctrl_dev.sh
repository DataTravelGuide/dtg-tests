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

cbdctrl_backend_start $backend_node 0 $backend_blk "" 1 false
cbdctrl_backend_start $backend_node 0 $backend_blk_2 "" 1 false

cbdctrl_dev_start $blkdev_node 1 0 true # invalid transport_id
cbdctrl_dev_start $blkdev_node 0 100 true # invalid backend id
cbdctrl_dev_start $blkdev_node 0 0 false
cbdctrl_dev_start $blkdev_node 0 1 false
run_remote_cmd $blkdev_node "mkfs.xfs -f /dev/cbd0"

cbdctrl_dev_stop $blkdev_node 0 0 false
cbdctrl_dev_stop $blkdev_node 0 1 false

cbdctrl_tp_unreg $backend_node 0 true # backend busy 

cbdctrl_backend_stop $backend_node 0 0
cbdctrl_backend_stop $backend_node 0 1

cbdctrl_tp_unreg $blkdev_node 0 "false"
if $multihost_mode; then
	cbdctrl_tp_unreg $backend_node 0 "false"
fi
