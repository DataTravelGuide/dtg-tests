#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"
: "${cache_dev0:=/dev/pmem0}"
: "${data_crc:=false}"
: "${gc_percent:=}"
: "${data_dev0:?data_dev0 not set}"

dm_name0="pcache_$(basename ${data_dev0})"

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko

reset_pmem() {
    dd if=/dev/zero of=${cache_dev0} bs=1M count=1 oflag=direct
    sync
}

export linux_path cache_dev0 data_crc gc_percent data_dev0 dm_name0
export -f reset_pmem

test_dir="$(dirname "$0")/pcache_mics_tests"

for tc in "$test_dir"/*.sh; do
    echo "===== Running $(basename "$tc") ====="
    bash "$tc"
    echo "===== Finished $(basename "$tc") ====="
done

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
