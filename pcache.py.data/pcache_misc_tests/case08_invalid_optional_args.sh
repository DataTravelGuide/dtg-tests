#!/bin/bash
set -e
reset_pmem
SEC_NR=$(sudo blockdev --getsz ${data_dev0})

echo "DEBUG: case 8 - invalid number_of_optional_arguments should fail"
if sudo dmsetup create pcache_invalid --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} INVAL cache_mode writeback data_crc ${data_crc}"; then
    echo "dmsetup create succeeded with invalid optional args"
    sudo dmsetup remove pcache_invalid
    exit 1
fi
if sudo dmsetup create pcache_invalid --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 100 cache_mode writeback data_crc ${data_crc}"; then
    echo "dmsetup create succeeded with invalid optional args"
    sudo dmsetup remove pcache_invalid
    exit 1
fi
