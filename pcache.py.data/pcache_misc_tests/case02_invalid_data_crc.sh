#!/bin/bash
set -e
reset_pmem
SEC_NR=$(sudo blockdev --getsz ${data_dev0})

echo "DEBUG: case 2 - invalid data_crc should fail"
if sudo dmsetup create pcache_invalid --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode writeback data_crc invalid"; then
    echo "dmsetup create succeeded with invalid data_crc"
    sudo dmsetup remove pcache_invalid
    exit 1
fi
