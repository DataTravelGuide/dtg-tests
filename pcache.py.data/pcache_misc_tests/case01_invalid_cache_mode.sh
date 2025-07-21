#!/bin/bash
set -e
: "${cache_mode:=writeback}"
reset_pmem
SEC_NR=$(sudo blockdev --getsz ${data_dev0})

echo "DEBUG: case 1 - invalid cache mode should fail"

if sudo dmsetup create pcache_invalid --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode invalid data_crc ${data_crc}"; then
    echo "dmsetup create succeeded with invalid cache_mode"
    sudo dmsetup remove pcache_invalid
    exit 1
fi
