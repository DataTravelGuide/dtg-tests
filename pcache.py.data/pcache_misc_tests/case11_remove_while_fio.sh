#!/bin/bash
set -e
reset_pmem

echo "DEBUG: case 11 - remove pcache while fio running"
fio --name=pcachetest --filename=/dev/mapper/${dm_name0} --rw=randwrite --bs=4k --runtime=10 --time_based=1 --ioengine=libaio --direct=1 &
fio_pid=$!
sleep 2
sudo dmsetup remove --force ${dm_name0} || true
wait ${fio_pid} || true

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
