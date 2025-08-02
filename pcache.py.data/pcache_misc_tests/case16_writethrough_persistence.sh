#!/bin/bash
set -ex
sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko 2>/dev/null || true
: "${cache_mode:=writeback}"
reset_pmem

if [[ "${cache_mode}" != "writethrough" ]]; then
    echo "cache_mode is ${cache_mode}, skipping writethrough test"
    exit 0
fi
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
if ! sudo dmsetup create ${dm_name0}_probe --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove ${dm_name0}_probe
reset_pmem


echo "DEBUG: case 16 - verify writethrough mode writes directly to backing device"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

dd if=/dev/urandom of=/mnt/pcache/testfile bs=1M count=5
orig_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')

status=$(sudo dmsetup status ${dm_name0})
read -ra fields <<< "$status"
len=${#fields[@]}
dirty_tail=${fields[$((len - 2))]}
if [[ "${dirty_tail}" != "0:0" ]]; then
    echo "dirty_tail is ${dirty_tail}, expected 0:0"
    exit 1
fi

sync
sudo umount /mnt/pcache
sudo dmsetup remove ${dm_name0}

sudo mount ${data_dev0} /mnt/pcache
new_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after removing pcache"
    exit 1
fi
sudo umount /mnt/pcache

sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
