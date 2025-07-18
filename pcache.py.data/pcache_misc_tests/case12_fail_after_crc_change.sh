#!/bin/bash
set -e
reset_pmem

echo "DEBUG: case 12 - dmsetup create should fail after data_crc change"
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode writeback data_crc ${data_crc}"
sudo dmsetup remove ${dm_name0}

if [[ "${data_crc}" == "true" ]]; then
    new_crc=false
else
    new_crc=true
fi
if sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode writeback data_crc ${new_crc}"; then
    echo "dmsetup create succeeded after data_crc change"
    sudo dmsetup remove ${dm_name0}
    exit 1
fi

sudo rmmod dm-pcache 2>/dev/null || true
