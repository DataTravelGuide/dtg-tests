#!/bin/bash
set -e
reset_pmem
SEC_NR=$(sudo blockdev --getsz ${data_dev0})

echo "DEBUG: case 4 - empty data_crc should fail"
if sudo dmsetup create pcache_invalid --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode writeback"; then
    echo "dmsetup create succeeded with empty data_crc"
    sudo dmsetup remove pcache_invalid
    exit 1
fi
