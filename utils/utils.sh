#!/bin/bash

setup ()
{
	# prepare ramdisk for testing.
	modprobe cbd

	echo "path=/dev/pmem0,hostname=node1,force=1,format=1" >  /sys/bus/cbd/transport_register
	echo "op=backend-start,path=/dev/vdc" > /sys/bus/cbd/devices/transport0/adm
	echo "op=backend-start,path=/dev/vdd" > /sys/bus/cbd/devices/transport0/adm

	echo "op=dev-start,backend_id=0,queues=1" > /sys/bus/cbd/devices/transport0/adm
	echo "op=dev-start,backend_id=1,queues=32" > /sys/bus/cbd/devices/transport0/adm

	echo "op=backend-start,path=/dev/vde,cache_size=160" > /sys/bus/cbd/devices/transport0/adm
	echo "op=backend-start,path=/dev/vdf,cache_size=5120" > /sys/bus/cbd/devices/transport0/adm

	echo "op=dev-start,backend_id=2,queues=1" > /sys/bus/cbd/devices/transport0/adm
	echo "op=dev-start,backend_id=3,queues=32" > /sys/bus/cbd/devices/transport0/adm

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

	echo "op=dev-stop,dev_id=0" > /sys/bus/cbd/devices/transport0/adm
	echo "op=dev-stop,dev_id=1" > /sys/bus/cbd/devices/transport0/adm
	echo "op=dev-stop,dev_id=2" > /sys/bus/cbd/devices/transport0/adm
	echo "op=dev-stop,dev_id=3" > /sys/bus/cbd/devices/transport0/adm
	sleep 3
	echo "op=backend-stop,backend_id=0" > /sys/bus/cbd/devices/transport0/adm
	echo "op=backend-stop,backend_id=1" > /sys/bus/cbd/devices/transport0/adm
	echo "op=backend-stop,backend_id=2" > /sys/bus/cbd/devices/transport0/adm
	echo "op=backend-stop,backend_id=3" > /sys/bus/cbd/devices/transport0/adm

	echo "transport_id=0" > /sys/bus/cbd/transport_unregister 

	rmmod cbd
}


replace_option()
{
	file=$1
	old=$2
	new=$3
	sed -i "s#${old}#${new}#" ${file}
}
