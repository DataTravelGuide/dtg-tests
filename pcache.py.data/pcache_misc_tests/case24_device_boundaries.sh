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

# Skip writeonly mode for boundary tests (no read support)
if [[ "${cache_mode}" == "writeonly" ]]; then
    echo "cache_mode is ${cache_mode}, skipping boundary tests"
    exit 0
fi

echo "DEBUG: case 24 - device boundary conditions"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})

# Test 1: Cache device larger than backing device
echo "Testing cache device larger than backing device..."
LARGE_CACHE_FILE="/tmp/large_cache.img"
LARGE_CACHE_SIZE=$((SEC_NR * 512 + 1024*1024))  # Slightly larger than backing device
dd if=/dev/zero of="${LARGE_CACHE_FILE}" bs=1M count=10  # Create 10MB cache file
LARGE_CACHE_LOOP=$(sudo losetup --find --show "${LARGE_CACHE_FILE}")

if [[ -n "${LARGE_CACHE_LOOP}" ]]; then
    if sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${LARGE_CACHE_LOOP} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
        echo "Large cache device creation succeeded"

        # Test basic functionality
        sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
        sudo mkdir -p /mnt/pcache
        sudo mount /dev/mapper/${dm_name0} /mnt/pcache

        # Write data that exceeds backing device size (should fail gracefully)
        if dd if=/dev/zero of=/mnt/pcache/largefile bs=1M count=100 2>/dev/null; then
            echo "Writing beyond device size succeeded unexpectedly"
            exit 1
        else
            echo "Writing beyond device size failed as expected"
        fi

        # Write normal amount of data
        dd if=/dev/urandom of=/mnt/pcache/normalfile bs=1M count=1
        orig_md5=$(md5sum /mnt/pcache/normalfile | awk '{print $1}')

        sudo umount /mnt/pcache
        sudo dmsetup remove ${dm_name0}

        # Recreate and verify
        sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${LARGE_CACHE_LOOP} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
        sudo mount /dev/mapper/${dm_name0} /mnt/pcache
        new_md5=$(md5sum /mnt/pcache/normalfile | awk '{print $1}')

        if [[ "${orig_md5}" != "${new_md5}" ]]; then
            echo "MD5 mismatch with large cache"
            exit 1
        fi

        sudo umount /mnt/pcache
        sudo dmsetup remove ${dm_name0}
    else
        echo "Large cache device creation failed"
    fi

    sudo losetup -d "${LARGE_CACHE_LOOP}"
    rm -f "${LARGE_CACHE_FILE}"
fi

# Test 2: Misaligned device sizes
echo "Testing misaligned device sizes..."
MISALIGN_CACHE_FILE="/tmp/misalign_cache.img"
dd if=/dev/zero of="${MISALIGN_CACHE_FILE}" bs=512 count=2049  # 2049 sectors (not aligned to 1MB)
MISALIGN_CACHE_LOOP=$(sudo losetup --find --show "${MISALIGN_CACHE_FILE}")

if [[ -n "${MISALIGN_CACHE_LOOP}" ]]; then
    if sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${MISALIGN_CACHE_LOOP} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
        echo "Misaligned cache device creation succeeded"

        # Basic functionality test
        sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
        sudo mount /dev/mapper/${dm_name0} /mnt/pcache

        echo "misalign test" | sudo tee /mnt/pcache/testfile >/dev/null
        content=$(cat /mnt/pcache/testfile)
        if [[ "${content}" != "misalign test" ]]; then
            echo "Misaligned cache basic test failed"
            exit 1
        fi

        sudo umount /mnt/pcache
        sudo dmsetup remove ${dm_name0}
    else
        echo "Misaligned cache device creation failed"
    fi

    sudo losetup -d "${MISALIGN_CACHE_LOOP}"
    rm -f "${MISALIGN_CACHE_FILE}"
fi

# Test 3: Zero-sized operations (edge case)
echo "Testing zero-sized operations..."
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

# Try zero-sized read/write (should not crash)
dd if=/dev/zero of=/mnt/pcache/zerofile bs=1 count=0
dd if=/mnt/pcache/zerofile of=/dev/null bs=1 count=0

sudo umount /mnt/pcache
sudo dmsetup remove ${dm_name0}

echo "Device boundary tests completed successfully"

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
pcache_rmmod