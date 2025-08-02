#!/bin/bash
set -ex
sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
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

echo "DEBUG: case 8 - invalid number_of_optional_arguments should fail"
if sudo dmsetup create pcache_invalid --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} INVAL cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "dmsetup create succeeded with invalid optional args"
    sudo dmsetup remove pcache_invalid
    exit 1
fi
if sudo dmsetup create pcache_invalid --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 100 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "dmsetup create succeeded with invalid optional args"
    sudo dmsetup remove pcache_invalid
    exit 1
fi
sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
