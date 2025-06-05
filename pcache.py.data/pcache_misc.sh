#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"
: "${cache_dev0:=/dev/pmem0}"
: "${data_crc:=false}"
: "${gc_percent:=}"

sudo dmsetup remove pcache_ram0p1 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
sudo rmmod brd 2>/dev/null || true

sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko
sudo insmod ${linux_path}/drivers/block/brd.ko rd_nr=1 rd_size=$((22*1024*1024))

sudo parted /dev/ram0 mklabel gpt
sudo sgdisk /dev/ram0 -n 1:1M:+10G

dd if=/dev/zero of=${cache_dev0} bs=1M count=1

SEC_NR=$(sudo blockdev --getsz /dev/ram0p1)
echo "0 ${SEC_NR} pcache ${cache_dev0} /dev/ram0p1 writeback ${data_crc}" | sudo dmsetup create pcache_ram0p1

if [[ -n "${gc_percent}" ]]; then
    sudo dmsetup message pcache_ram0p1 0 gc_percent ${gc_percent}
fi

sudo mkfs.ext4 -F /dev/mapper/pcache_ram0p1
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/pcache_ram0p1 /mnt/pcache

dd if=/dev/urandom of=/mnt/pcache/testfile bs=1M count=10
orig_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')
sudo umount /mnt/pcache

sudo dmsetup remove pcache_ram0p1

echo "0 ${SEC_NR} pcache ${cache_dev0} /dev/ram0p1 writeback ${data_crc}" | sudo dmsetup create pcache_ram0p1
sudo mount /dev/mapper/pcache_ram0p1 /mnt/pcache
new_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after recreate"
    exit 1
fi
sudo umount /mnt/pcache

fio --name=pcachetest --filename=/dev/mapper/pcache_ram0p1 --rw=randwrite --bs=4k --runtime=10 --time_based=1 --ioengine=sync --direct=1 &
fio_pid=$!
sleep 2
sudo dmsetup remove --force pcache_ram0p1 || true
wait ${fio_pid} || true

sudo dmsetup remove pcache_ram0p1 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
sudo rmmod brd 2>/dev/null || true
