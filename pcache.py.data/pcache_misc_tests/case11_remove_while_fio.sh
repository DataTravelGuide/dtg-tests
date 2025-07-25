#!/bin/bash
set -ex
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko 2>/dev/null || true
: "${cache_mode:=writeback}"
reset_pmem
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
if ! sudo dmsetup create ${dm_name0}_probe --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove ${dm_name0}_probe
reset_pmem

echo "DEBUG: case 11 - remove pcache while fio running"
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
fio --name=pcachetest --filename=/dev/mapper/${dm_name0} --rw=randwrite --bs=4k --runtime=10 --time_based=1 --ioengine=libaio --direct=1 &
fio_pid=$!
sleep 2
sudo dmsetup remove --force ${dm_name0} || true
wait ${fio_pid} || true

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
