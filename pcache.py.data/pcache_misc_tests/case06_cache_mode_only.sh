#!/bin/bash
set -e
: "${cache_mode:=writeback}"
reset_pmem
SEC_NR=$(sudo blockdev --getsz ${data_dev0})

echo "DEBUG: case 6 - cache_mode only"
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 2 cache_mode ${cache_mode}"
sudo dmsetup remove ${dm_name0}
