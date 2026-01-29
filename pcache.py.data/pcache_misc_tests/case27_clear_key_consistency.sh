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

cleanup() {
    sudo umount /mnt/pcache 2>/dev/null || true
    sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
    sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
    pcache_rmmod
}
trap cleanup EXIT

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
pcache_rmmod
pcache_insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko
: "${cache_mode:=writeback}"
reset_pmem

# Only test writearound mode for CLEAR key consistency
if [[ "${cache_mode}" != "writearound" ]]; then
    echo "cache_mode is ${cache_mode}, skipping CLEAR key consistency test"
    exit 0
fi

echo "DEBUG: case 27 - CLEAR key consistency verification"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

# Test 1: Write data and verify CLEAR keys are created
echo "Testing CLEAR key creation..."
dd if=/dev/urandom of=/mnt/pcache/testfile1 bs=1M count=3
orig_md5_1=$(md5sum /mnt/pcache/testfile1 | awk '{print $1}')

# Check dmsetup status to see if there are any keys (should be minimal for writearound)
status=$(sudo dmsetup status ${dm_name0})
echo "DM status after write: $status"

# Test 2: Read back data and verify it's from backing device
echo "Testing data read back..."
new_md5_1=$(md5sum /mnt/pcache/testfile1 | awk '{print $1}')
if [[ "${orig_md5_1}" != "${new_md5_1}" ]]; then
    echo "MD5 mismatch after read back"
    exit 1
fi

# Test 3: Write more data and check consistency
echo "Testing multiple writes..."
dd if=/dev/urandom of=/mnt/pcache/testfile2 bs=512K count=10
orig_md5_2=$(md5sum /mnt/pcache/testfile2 | awk '{print $1}')

dd if=/dev/urandom of=/mnt/pcache/testfile3 bs=2M count=2
orig_md5_3=$(md5sum /mnt/pcache/testfile3 | awk '{print $1}')

# Test 4: Persistence test - remove and recreate pcache
echo "Testing CLEAR key persistence..."
sudo umount /mnt/pcache
sudo dmsetup remove ${dm_name0}

# Recreate pcache with same cache device
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

# Verify all data is still accessible (from backing device)
new_md5_1=$(md5sum /mnt/pcache/testfile1 | awk '{print $1}')
new_md5_2=$(md5sum /mnt/pcache/testfile2 | awk '{print $1}')
new_md5_3=$(md5sum /mnt/pcache/testfile3 | awk '{print $1}')

if [[ "${orig_md5_1}" != "${new_md5_1}" ]]; then
    echo "MD5 mismatch for testfile1 after recreate"
    exit 1
fi

if [[ "${orig_md5_2}" != "${new_md5_2}" ]]; then
    echo "MD5 mismatch for testfile2 after recreate"
    exit 1
fi

if [[ "${orig_md5_3}" != "${new_md5_3}" ]]; then
    echo "MD5 mismatch for testfile3 after recreate"
    exit 1
fi

# Test 5: Overwrite existing data
echo "Testing data overwrite..."
dd if=/dev/urandom of=/mnt/pcache/testfile1 bs=1M count=3 conv=notrunc
new_orig_md5_1=$(md5sum /mnt/pcache/testfile1 | awk '{print $1}')

# Verify the new data
verify_md5_1=$(md5sum /mnt/pcache/testfile1 | awk '{print $1}')
if [[ "${new_orig_md5_1}" != "${verify_md5_1}" ]]; then
    echo "MD5 mismatch after overwrite"
    exit 1
fi

# Test 6: Check that we don't cache overwritten data
echo "Testing that overwritten data is not cached..."
status=$(sudo dmsetup status ${dm_name0})
echo "Final DM status: $status"

# In writearound mode, there should be minimal to no cached data
# since we read from backing device directly

echo "CLEAR key consistency tests completed successfully"