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

# Skip writeonly mode for concurrent IO tests (limited read support)
if [[ "${cache_mode}" == "writeonly" ]]; then
    echo "cache_mode is ${cache_mode}, skipping concurrent IO tests"
    exit 0
fi

echo "DEBUG: case 25 - concurrent IO operations"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

# Test 1: Multiple sequential read/write operations
echo "Testing multiple sequential operations..."
for i in {1..5}; do
    dd if=/dev/urandom of=/mnt/pcache/file${i} bs=1M count=2 &
done
wait

# Verify all files were written
declare -a orig_md5
for i in {1..5}; do
    if [[ ! -f /mnt/pcache/file${i} ]]; then
        echo "File file${i} was not created"
        exit 1
    fi
    orig_md5[$i]=$(md5sum /mnt/pcache/file${i} | awk '{print $1}')
done

# Test 2: Concurrent read and write operations
echo "Testing concurrent read/write operations..."
dd if=/dev/urandom of=/mnt/pcache/largefile bs=1M count=10 &
dd if=/mnt/pcache/file1 of=/dev/null bs=1M &
dd if=/dev/urandom of=/mnt/pcache/concurrent_file bs=512K count=10 &
wait

# Test 3: Mixed operations with different patterns
echo "Testing mixed operation patterns..."
# Small file operations
for i in {1..10}; do
    echo "small file ${i}" > /mnt/pcache/small${i}.txt &
done
wait

# Large file operations
dd if=/dev/zero of=/mnt/pcache/zeros bs=1M count=5 &
dd if=/dev/urandom of=/mnt/pcache/random bs=1M count=3 &
wait

# Directory operations
mkdir -p /mnt/pcache/dir1 /mnt/pcache/dir2
mv /mnt/pcache/small*.txt /mnt/pcache/dir1/ &
cp /mnt/pcache/file1 /mnt/pcache/dir2/copied_file &
wait

# Test 4: Verify data integrity after concurrent operations
echo "Verifying data integrity..."
for i in {1..5}; do
    new_md5=$(md5sum /mnt/pcache/file${i} | awk '{print $1}')
    if [[ "${orig_md5[$i]}" != "${new_md5}" ]]; then
        echo "MD5 mismatch for file${i} after concurrent operations"
        echo "Expected: ${orig_md5[$i]}"
        echo "Got: ${new_md5}"
        exit 1
    fi
done

# Test 5: Filesystem integrity check
echo "Checking filesystem integrity..."
sudo umount /mnt/pcache
sudo e2fsck -n /dev/mapper/${dm_name0}

echo "Concurrent IO tests completed successfully"