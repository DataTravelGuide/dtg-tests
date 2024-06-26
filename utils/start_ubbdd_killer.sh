#!/bin/bash

wait_for_cbdd ()
{
	while true ; do
		cbdadm list
		if [ $? -eq 0 ]; then
			return
		fi
		sleep 1
	done
}

sleep_time=$1

while true; do
	pkill -9 cbd-backend
	pkill -9 cbdd
	ps -ef|grep cbdd|grep memleak|gawk '{print "kill "$2}'|bash

	wait_for_cbdd
	sleep $(($RANDOM % ${sleep_time}))
done
