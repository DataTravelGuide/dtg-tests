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

# Skip writeonly mode for performance benchmarks (limited operations)
if [[ "${cache_mode}" == "writeonly" ]]; then
    echo "cache_mode is ${cache_mode}, skipping performance benchmarks"
    exit 0
fi

echo "DEBUG: case 29 - performance benchmark for ${cache_mode} mode"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

# Function to measure performance
measure_performance() {
    local operation=$1
    local bs=$2
    local count=$3
    local file=$4

    echo "Measuring $operation performance (bs=${bs}, count=${count})..."

    local start_time=$(date +%s)
    case $operation in
        "write")
            dd if=/dev/zero of=/mnt/pcache/$file bs=$bs count=$count oflag=direct 2>/dev/null
            ;;
        "read")
            dd if=/mnt/pcache/$file of=/dev/null bs=$bs count=$count iflag=direct 2>/dev/null
            ;;
        "rewrite")
            dd if=/dev/zero of=/mnt/pcache/$file bs=$bs count=$count conv=notrunc oflag=direct 2>/dev/null
            ;;
    esac
    local end_time=$(date +%s)

    # Calculate throughput (MB/s)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    local data_size=$(echo "$bs * $count / 1024 / 1024" | bc -l)
    local throughput=$(echo "scale=2; $data_size / $duration" | bc -l)

    echo "$operation: ${throughput} MB/s (${duration}s for ${data_size}MB)"
}

# Test 1: Sequential write performance
echo "=== Sequential Write Performance ==="
measure_performance "write" "1M" "50" "seq_write_1m"
measure_performance "write" "4K" "10000" "seq_write_4k"

# Test 2: Sequential read performance (test cache hit)
echo "=== Sequential Read Performance ==="
measure_performance "read" "1M" "50" "seq_write_1m"
measure_performance "read" "4K" "10000" "seq_write_4k"

# Test 3: Random I/O performance
echo "=== Random I/O Performance ==="
# Create test file with random data
dd if=/dev/urandom of=/mnt/pcache/random_test bs=1M count=20 oflag=direct 2>/dev/null

# Use fio for random I/O if available
if command -v fio >/dev/null 2>&1; then
    echo "Using fio for random I/O benchmark..."
    cat > /tmp/fio_config.ini << EOF
[global]
bs=4k
size=10m
numjobs=1
runtime=10
time_based=1

[randread]
rw=randread
filename=/mnt/pcache/random_test

[randwrite]
rw=randwrite
filename=/mnt/pcache/randwrite_test
EOF

    fio /tmp/fio_config.ini --output=/tmp/fio_results.txt
    grep -E "(read|write):.*bw=" /tmp/fio_results.txt || echo "FIO results not found"
else
    echo "fio not available, skipping random I/O benchmark"
fi

# Test 4: Cache hit ratio estimation
echo "=== Cache Hit Ratio Estimation ==="
# Clear cache by recreating device
sudo umount /mnt/pcache
sudo dmsetup remove ${dm_name0}

sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

# Measure cold cache read
echo "Cold cache read:"
measure_performance "read" "1M" "10" "seq_write_1m"

# Measure warm cache read (should be faster if cached)
echo "Warm cache read:"
measure_performance "read" "1M" "10" "seq_write_1m"

# Test 5: Mode-specific performance characteristics
echo "=== Mode-specific Performance Analysis ==="
case "${cache_mode}" in
    "writeback")
        echo "Writeback mode: Writes should be fast (cached), reads may have cache misses"
        ;;
    "writethrough")
        echo "Writethrough mode: Writes should be slower (dual writes), reads benefit from cache"
        ;;
    "writearound")
        echo "Writearound mode: Writes bypass cache, reads always hit backing device"
        ;;
esac

# Test 6: Memory usage and cache statistics
echo "=== Cache Statistics ==="
status=$(sudo dmsetup status ${dm_name0})
echo "Final device status: $status"

# Extract key metrics
read -ra fields <<< "$status"
key_head=${fields[6]}
key_tail=${fields[8]}
dirty_tail=${fields[10]}

echo "Key head: $key_head"
echo "Key tail: $key_tail"
echo "Dirty tail: $dirty_tail"

echo "Performance benchmark completed for ${cache_mode} mode"