#!/bin/bash
set -e
reset_pmem
SEC_NR=$(sudo blockdev --getsz ${data_dev0})

echo "DEBUG: case 5 - create without optional arguments"
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0}"
sudo dmsetup remove ${dm_name0}
