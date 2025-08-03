#!/bin/bash
set -ex

: "${covdir:=/workspace/datatravelguide/covdir}"
: "${gcov:=false}"

dump_gcov() {
    [[ "$gcov" != "true" ]] && return
    ts=$(date +%s)
    mkdir -p "$covdir"
    sudo find /sys/kernel/debug/gcov -path "*dm-pcache*gcda" -exec sh -c 'cp "$1" "$2/$3_$(basename "$1")"' _ {} "$covdir" "$ts" \;
    sudo find /sys/kernel/debug/gcov -path "*dm-pcache*gcno" -exec sh -c 'cp "$1" "$2/$3_$(basename "$1")"' _ {} "$covdir" "$ts" \;
}


pcache_rmmod() {
    dump_gcov
    sudo rmmod dm-pcache 2>/dev/null || true
}

reset_gcov() {
    [[ "$gcov" != "true" ]] && return
    echo 1 | sudo tee /sys/kernel/debug/gcov/reset >/dev/null
}

pcache_insmod() {
    reset_gcov
    sudo insmod "$1"
}

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
pcache_rmmod
pcache_insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko
: "${cache_mode:=writeback}"
reset_pmem

if [[ "${cache_mode}" != "writearound" ]]; then
    echo "cache_mode is ${cache_mode}, skipping writearound test"

    exit 0
fi
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
if ! sudo dmsetup create ${dm_name0}_probe --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove ${dm_name0}_probe
reset_pmem


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
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
pcache_rmmod
