#!/bin/bash
set -e
reset_pmem
SEC_NR=$(sudo blockdev --getsz ${data_dev0})

echo "DEBUG: case 3 - empty cache_mode should fail"
if sudo dmsetup create pcache_invalid --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 data_crc ${data_crc}"; then
    echo "dmsetup create succeeded with empty cache_mode"
    sudo dmsetup remove pcache_invalid
    exit 1
fi
