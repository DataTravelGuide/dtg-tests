#!/bin/bash
set -e
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko 2>/dev/null || true
: "${cache_mode:=writeback}"
reset_pmem

echo "DEBUG: case 15 - dmsetup create should fail after cache_mode change"
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
sudo dmsetup remove ${dm_name0}

if [[ "${cache_mode}" == "writeback" ]]; then
    new_mode=writethrough
else
    new_mode=writeback
fi
if sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${new_mode} data_crc ${data_crc}"; then
    echo "dmsetup create succeeded after cache_mode change"
    sudo dmsetup remove ${dm_name0}
    exit 1
fi

sudo rmmod dm-pcache 2>/dev/null || true
