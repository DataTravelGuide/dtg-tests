#!/bin/bash

setup ()
{
	# prepare ramdisk for testing.
	modprobe cbd

	cbdctrl tp-reg --path /dev/pmem0 --host node1 --force --format
	cbdctrl backend-start --path /dev/vdc --handlers 1
	cbdctrl backend-start --path /dev/vdd --handlers 32

	cbdctrl dev-start --backend 0
	cbdctrl dev-start --backend 1

	cbdctrl backend-start --path /dev/vde --handlers 1 --cache-size 160M
	cbdctrl backend-start --path /dev/vdf --handlers 32 --cache-size 5120M

	cbdctrl dev-start --backend 2
	cbdctrl dev-start --backend 3

	mkfs.xfs -f /dev/cbd0
	mkfs.xfs -f /dev/cbd2
}


cleanup ()
{
	if mount | grep "$XFSTESTS_SCRATCH_MNT"; then
		umount $XFSTESTS_SCRATCH_MNT
	fi

	if mount | grep "$XFSTESTS_TEST_MNT"; then
		umount $XFSTESTS_TEST_MNT
	fi

	cbdctrl dev-stop --dev 0
	cbdctrl dev-stop --dev 1
	cbdctrl dev-stop --dev 2
	cbdctrl dev-stop --dev 3
	cbdctrl backend-stop --backend 0
	cbdctrl backend-stop --backend 1
	cbdctrl backend-stop --backend 2
	cbdctrl backend-stop --backend 3

	cbdctrl tp-unreg --transport 0

	rmmod cbd
}


replace_option()
{
	file=$1
	old=$2
	new=$3
	sed -i "s#${old}#${new}#" ${file}
}
