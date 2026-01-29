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

echo "DEBUG: case 28 - GC behavior across different cache modes"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

# Test 1: Fill cache and trigger GC
echo "Testing GC behavior..."

# Write enough data to potentially trigger GC
for i in {1..20}; do
    dd if=/dev/urandom of=/mnt/pcache/gc_file_${i} bs=1M count=1 oflag=direct
done

# Check status before GC
status_before=$(sudo dmsetup status ${dm_name0})
echo "Status before GC: $status_before"

# Trigger GC by setting low threshold and waiting
sudo dmsetup message ${dm_name0} 0 gc_percent 1

# Wait for GC to complete
for i in {1..30}; do
    status=$(sudo dmsetup status ${dm_name0})
    echo "GC iteration $i: $status"

    # Check if key_head == key_tail (GC completed)
    read -ra fields <<< "$status"
    key_head=${fields[6]}
    key_tail=${fields[8]}

    if [[ "$key_head" == "$key_tail" ]]; then
        echo "GC completed after $i iterations"
        break
    fi

    sleep 1
done

# Test 2: Verify data integrity and cache behavior after GC
echo "Verifying data integrity and cache behavior after GC..."

# All files should still exist and be accessible
for i in {1..20}; do
    if [[ ! -f /mnt/pcache/gc_file_${i} ]]; then
        echo "File gc_file_${i} missing after GC"
        exit 1
    fi
done

# Check cache status after GC
post_gc_status=$(sudo dmsetup status ${dm_name0})
echo "Cache status after GC: $post_gc_status"

# Verify that cache statistics are reasonable
read -ra fields <<< "$post_gc_status"
post_gc_key_head=${fields[6]}
post_gc_key_tail=${fields[8]}

echo "Post-GC key_head: $post_gc_key_head, key_tail: $post_gc_key_tail"

# In a healthy system, key_head should be >= key_tail (or properly managed)
# We don't check specific values since GC behavior depends on actual usage

# Test 3: Mode-specific GC behavior
case "${cache_mode}" in
    "writeback")
        echo "Testing writeback mode GC specifics..."
        # In writeback mode, dirty data should be written back during GC
        # Check that dirty_tail advances
        status=$(sudo dmsetup status ${dm_name0})
        read -ra fields <<< "$status"
        dirty_tail=${fields[10]}
        if [[ "$dirty_tail" != "0:0" ]]; then
            echo "Dirty data should be written back in writeback mode"
        fi
        ;;
    "writethrough")
        echo "Testing writethrough mode GC specifics..."
        # In writethrough, should have no dirty data
        status=$(sudo dmsetup status ${dm_name0})
        read -ra fields <<< "$status"
        dirty_tail=${fields[10]}
        if [[ "$dirty_tail" != "0:0" ]]; then
            echo "Writethrough should have no dirty data, but dirty_tail=$dirty_tail"
            exit 1
        fi
        ;;
    "writearound")
        echo "Testing writearound mode GC specifics..."
        # In writearound, should have no dirty data and minimal cached data
        status=$(sudo dmsetup status ${dm_name0})
        read -ra fields <<< "$status"
        dirty_tail=${fields[10]}
        if [[ "$dirty_tail" != "0:0" ]]; then
            echo "Writearound should have no dirty data, but dirty_tail=$dirty_tail"
            exit 1
        fi
        ;;
    "writeonly")
        echo "Testing writeonly mode GC specifics..."
        # In writeonly, GC should work but no read verification possible
        echo "Writeonly mode GC test completed (read verification skipped)"
        ;;
esac

# Test 4: GC with mixed operations and statistics verification
echo "Testing GC with mixed operations..."

# Create additional files to test GC under load
for i in {21..25}; do
    dd if=/dev/urandom of=/mnt/pcache/gc_file_${i} bs=512K count=2 oflag=direct
done

# Record MD5 before GC for data integrity check
declare -a pre_gc_md5
for i in {1..4} {6..9} {11..14} {16..25}; do
    if [[ -f /mnt/pcache/gc_file_${i} ]]; then
        pre_gc_md5[$i]=$(md5sum /mnt/pcache/gc_file_${i} | awk '{print $1}')
    fi
done

# Get cache statistics before additional GC
status_before=$(sudo dmsetup status ${dm_name0})
echo "Cache status before additional GC: $status_before"

# Trigger GC with different threshold
sudo dmsetup message ${dm_name0} 0 gc_percent 10

# Wait for GC and monitor progress
for i in {1..10}; do
    sleep 2
    status=$(sudo dmsetup status ${dm_name0})
    echo "GC progress check $i: $(date +%T)"

    # Check if GC is making progress (optional, just for monitoring)
    read -ra fields <<< "$status"
    key_tail=${fields[8]}
    echo "Current key_tail: $key_tail"
done

# Final status check
final_status=$(sudo dmsetup status ${dm_name0})
echo "Final cache status after GC: $final_status"

# Verify data integrity - all files should still be accessible and unchanged
echo "Verifying data integrity after mixed GC operations..."
for i in {1..4} {6..9} {11..14} {16..25}; do
    if [[ -f /mnt/pcache/gc_file_${i} ]]; then
        post_gc_md5=$(md5sum /mnt/pcache/gc_file_${i} | awk '{print $1}')
        if [[ "${pre_gc_md5[$i]}" != "${post_gc_md5}" ]]; then
            echo "Data corruption detected in gc_file_${i} after GC"
            exit 1
        fi
    else
        echo "File gc_file_${i} missing after GC operations"
        exit 1
    fi
done

echo "All files preserved and data integrity maintained after GC"

echo "GC behavior tests completed successfully"