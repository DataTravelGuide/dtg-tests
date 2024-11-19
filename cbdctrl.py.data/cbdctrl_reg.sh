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

cbdctrl_tp_unreg $blkdev_node 0 "false"
if $multihost_mode; then
	cbdctrl_tp_unreg $backend_node 0 "false"
fi
