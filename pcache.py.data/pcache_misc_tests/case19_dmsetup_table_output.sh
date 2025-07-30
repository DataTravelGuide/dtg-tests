#!/bin/bash
set -ex
sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
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

echo "DEBUG: case 19 - verify dmsetup table output matches create parameters"

sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

cache_mm=$(lsblk -d -no MAJ:MIN ${cache_dev0} | tr -d ' ')
data_mm=$(lsblk -d -no MAJ:MIN ${data_dev0} | tr -d ' ')
expected="0 ${SEC_NR} pcache ${cache_mm} ${data_mm} 4 cache_mode ${cache_mode} crc ${data_crc}"

actual=$(sudo dmsetup table ${dm_name0})

if [[ "${actual}" != "${expected}" ]]; then
    echo "dmsetup table output mismatch"
    echo "Expected: ${expected}"
    echo "Actual:   ${actual}"
    sudo dmsetup remove ${dm_name0}
    exit 1
fi

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
