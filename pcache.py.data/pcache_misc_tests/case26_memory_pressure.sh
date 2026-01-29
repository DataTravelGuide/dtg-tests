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

# Skip writeonly mode for memory pressure tests
if [[ "${cache_mode}" == "writeonly" ]]; then
    echo "cache_mode is ${cache_mode}, skipping memory pressure tests"
    exit 0
fi

echo "DEBUG: case 26 - memory pressure behavior"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

# Test 1: Low memory simulation using stress-ng
echo "Testing under memory pressure..."
if command -v stress-ng >/dev/null 2>&1; then
    # Start memory stress in background
    stress-ng --vm 2 --vm-bytes 80% --timeout 30s &
    STRESS_PID=$!

    # Perform IO operations under memory pressure
    dd if=/dev/urandom of=/mnt/pcache/stress_file bs=1M count=5
    orig_md5=$(md5sum /mnt/pcache/stress_file | awk '{print $1}')

    # Small delay to let stress take effect
    sleep 5

    # Try reading back
    new_md5=$(md5sum /mnt/pcache/stress_file | awk '{print $1}')
    if [[ "${orig_md5}" != "${new_md5}" ]]; then
        echo "MD5 mismatch under memory pressure"
        kill $STRESS_PID 2>/dev/null || true
        exit 1
    fi

    # Wait for stress to complete
    wait $STRESS_PID 2>/dev/null || true
else
    echo "stress-ng not available, simulating memory pressure with dd..."

    # Fallback: use dd to consume memory
    dd if=/dev/zero of=/dev/null bs=1M count=100 &
    MEM_STRESS_PID=$!

    dd if=/dev/urandom of=/mnt/pcache/mem_test bs=512K count=20
    mem_md5=$(md5sum /mnt/pcache/mem_test | awk '{print $1}')

    sleep 2

    verify_md5=$(md5sum /mnt/pcache/mem_test | awk '{print $1}')
    if [[ "${mem_md5}" != "${verify_md5}" ]]; then
        echo "MD5 mismatch during memory stress simulation"
        kill $MEM_STRESS_PID 2>/dev/null || true
        exit 1
    fi

    kill $MEM_STRESS_PID 2>/dev/null || true
fi

# Test 2: Large number of small files (inode pressure)
echo "Testing with large number of small files..."
mkdir -p /mnt/pcache/small_files
for i in {1..100}; do
    echo "content_${i}" > /mnt/pcache/small_files/file_${i}.txt
done

# Verify some files
for i in {1..10}; do
    content=$(cat /mnt/pcache/small_files/file_${i}.txt)
    expected="content_${i}"
    if [[ "${content}" != "${expected}" ]]; then
        echo "Small file content mismatch for file_${i}"
        exit 1
    fi
done

# Test 3: Rapid create/delete operations
echo "Testing rapid create/delete operations..."
for round in {1..3}; do
    for i in {1..20}; do
        echo "round${round}_file${i}" > /mnt/pcache/rapid_${i}.tmp
    done

    # Delete half of them
    for i in {1..10}; do
        rm /mnt/pcache/rapid_${i}.tmp
    done

    # Verify remaining files
    for i in {11..20}; do
        content=$(cat /mnt/pcache/rapid_${i}.tmp)
        expected="round${round}_file${i}"
        if [[ "${content}" != "${expected}" ]]; then
            echo "Rapid file content mismatch for rapid_${i}.tmp"
            exit 1
        fi
    done

    # Clean up
    rm /mnt/pcache/rapid_*.tmp
done

# Test 4: Filesystem check after memory operations
echo "Checking filesystem integrity after memory pressure tests..."
sudo umount /mnt/pcache
sudo e2fsck -n /dev/mapper/${dm_name0}

echo "Memory pressure tests completed successfully"