#!/bin/bash
set -e
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko 2>/dev/null || true
: "${cache_mode:=writeback}"
reset_pmem

if [[ "${cache_mode}" != "writearound" ]]; then
    echo "cache_mode is ${cache_mode}, skipping writearound test"
    exit 0
fi

echo "DEBUG: case 17 - verify writearound mode behavior"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

# write initial data through pcache
dd if=/dev/urandom of=/mnt/pcache/testfile bs=1M count=5
orig_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')

sudo umount /mnt/pcache
sudo dmsetup remove ${dm_name0}

# validate backing device contains the data
sudo mount ${data_dev0} /mnt/pcache
back_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')
if [[ "${orig_md5}" != "${back_md5}" ]]; then
    echo "MD5 mismatch after removing pcache"
    exit 1
fi

# overwrite data directly on backing device
dd if=/dev/urandom of=/mnt/pcache/testfile bs=1M count=5 conv=fsync
new_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')
sudo umount /mnt/pcache

# recreate pcache using same cache device without resetting
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
sudo mount /dev/mapper/${dm_name0} /mnt/pcache
read_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')
if [[ "${new_md5}" != "${read_md5}" ]]; then
    echo "MD5 mismatch after recreating pcache"
    exit 1
fi
sudo umount /mnt/pcache

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
