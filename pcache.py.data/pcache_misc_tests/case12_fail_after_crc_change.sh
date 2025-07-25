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


echo "DEBUG: case 12 - dmsetup create should fail after data_crc change"
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
sudo dmsetup remove ${dm_name0}

if [[ "${data_crc}" == "true" ]]; then
    new_crc=false
else
    new_crc=true
fi
if sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${new_crc}"; then
    echo "dmsetup create succeeded after data_crc change"
    sudo dmsetup remove ${dm_name0}
    exit 1
fi

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
