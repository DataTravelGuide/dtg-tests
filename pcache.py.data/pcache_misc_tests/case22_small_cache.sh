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
    reset_gcov
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

if [[ "${cache_mode}" != "writeback" && "${cache_mode}" != "writethrough" ]]; then
    echo "cache_mode is ${cache_mode}, skipping small cache test for writeback/writethrough only"
    exit 0
fi

echo "DEBUG: case 22 - small cache device behavior"

# Test with a very small cache device (512KB - below minimum?)
SMALL_CACHE_SIZE=$((512 * 1024))  # 512KB
SEC_NR=$(sudo blockdev --getsz ${data_dev0})

# Create a small cache file
SMALL_CACHE_FILE="/tmp/small_cache.img"
dd if=/dev/zero of="${SMALL_CACHE_FILE}" bs=1 count=${SMALL_CACHE_SIZE}
SMALL_CACHE_LOOP=$(sudo losetup --find --show "${SMALL_CACHE_FILE}")

# Try to create pcache with small cache - this should fail or work minimally
if sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${SMALL_CACHE_LOOP} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "Small cache device creation succeeded unexpectedly"

    # Test basic functionality with minimal cache
    sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
    sudo mkdir -p /mnt/pcache
    sudo mount /dev/mapper/${dm_name0} /mnt/pcache

    # Write a small amount of data
    echo "test data" | sudo tee /mnt/pcache/testfile >/dev/null
    orig_content=$(cat /mnt/pcache/testfile)

    sudo umount /mnt/pcache
    sudo dmsetup remove ${dm_name0}

    # Recreate and verify data persistence
    sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${SMALL_CACHE_LOOP} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
    sudo mount /dev/mapper/${dm_name0} /mnt/pcache
    new_content=$(cat /mnt/pcache/testfile)

    if [[ "${orig_content}" != "${new_content}" ]]; then
        echo "Data mismatch with small cache"
        exit 1
    fi

    sudo umount /mnt/pcache
    sudo dmsetup remove ${dm_name0}
else
    echo "Small cache device creation failed as expected"
fi

# Cleanup
sudo losetup -d "${SMALL_CACHE_LOOP}"
rm -f "${SMALL_CACHE_FILE}"

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
pcache_rmmod