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

echo "DEBUG: case 2 - invalid data_crc should fail"
if sudo dmsetup create pcache_invalid --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc invalid"; then
    echo "dmsetup create succeeded with invalid data_crc"
    sudo dmsetup remove pcache_invalid
    exit 1
fi
sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
