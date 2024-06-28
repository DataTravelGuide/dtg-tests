#!/bin/bash

setup ()
{
	# prepare ramdisk for testing.
	modprobe brd rd_nr=1 rd_size=$((21*1024*1024)) max_part=16

	parted /dev/ram0 mklabel gpt
	sgdisk  /dev/ram0 -n 1:1M:+1000M
	sgdisk  /dev/ram0 -n 2:1001M:+10G
	sgdisk  /dev/ram0 -n 3:11241M:+10G

	partprobe /dev/ram0

	modprobe cbd

	echo "path=/dev/pmem0,hostname=node1,force=1,format=1" >  /sys/bus/cbd/transport_register
	echo "op=backend-start,path=/dev/ram0p2" > /sys/bus/cbd/devices/transport0/adm
	echo "op=backend-start,path=/dev/ram0p3" > /sys/bus/cbd/devices/transport0/adm
	echo "op=backend-start,path=/dev/sdb" > /sys/bus/cbd/devices/transport0/adm

	echo "op=dev-start,backend_id=0,queues=1" > /sys/bus/cbd/devices/transport0/adm
	echo "op=dev-start,backend_id=1,queues=1" > /sys/bus/cbd/devices/transport0/adm
	echo "op=dev-start,backend_id=2,queues=1" > /sys/bus/cbd/devices/transport0/adm

	mkfs.xfs -f /dev/cbd0
}


cleanup ()
{
	umount /mnt
	umount /media

	echo "op=dev-stop,dev_id=0" > /sys/bus/cbd/devices/transport0/adm
	echo "op=dev-stop,dev_id=1" > /sys/bus/cbd/devices/transport0/adm
	echo "op=dev-stop,dev_id=2" > /sys/bus/cbd/devices/transport0/adm
	sleep 3
	echo "op=backend-stop,backend_id=0" > /sys/bus/cbd/devices/transport0/adm
	echo "op=backend-stop,backend_id=1" > /sys/bus/cbd/devices/transport0/adm
	echo "op=backend-stop,backend_id=2" > /sys/bus/cbd/devices/transport0/adm

	echo "transport_id=0" > /sys/bus/cbd/transport_unregister 

	rmmod cbd
	rmmod brd
}


replace_option()
{
	file=$1
	old=$2
	new=$3
	sed -i "s#${old}#${new}#" ${file}
}
