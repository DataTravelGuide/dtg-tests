#!/bin/bash
set -e
reset_pmem

echo "DEBUG: case 14 - verify data consistency under heavy IO"
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode writeback data_crc ${data_crc}"

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

dd if=/dev/urandom of=/mnt/pcache/heavyfile bs=1M count=50
orig_md5=$(md5sum /mnt/pcache/heavyfile | awk '{print $1}')

if [[ -n "${gc_percent}" ]]; then
    sudo dmsetup message ${dm_name0} 0 gc_percent ${gc_percent}
fi

dd if=/mnt/pcache/heavyfile of=/mnt/pcache/loadfile bs=4k oflag=direct iflag=fullblock
new_md5=$(md5sum /mnt/pcache/loadfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after copy"
    exit 1
fi

fio --name=pcacheheavy --ioengine=libaio \
    --filename=/mnt/pcache/stressfile --rw=randwrite --size=100m \
    --runtime=20 --time_based=1 --bs=4k --direct=1 \
    --numjobs=4 --iodepth=16

new_md5=$(md5sum /mnt/pcache/loadfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after heavy IO"
    exit 1
fi

sync
sudo umount /mnt/pcache
sudo dmsetup remove ${dm_name0}

sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode writeback data_crc ${data_crc}"
sudo mount /dev/mapper/${dm_name0} /mnt/pcache
new_md5=$(md5sum /mnt/pcache/heavyfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after heavy IO"
    exit 1
fi
sudo umount /mnt/pcache

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
