#!/bin/bash
set -ex

: "${covdir:=/workspace/datatravelguide/covdir}"

dump_gcov() {
    ts=$(date +%s)
    mkdir -p "$covdir"
    sudo find /sys/kernel/debug/gcov -path "*dm-pcache*gcda" -exec sh -c 'cp "$1" "$2/$(basename "$1").$3"' _ {} "$covdir" "$ts" \;
    sudo find /sys/kernel/debug/gcov -path "*dm-pcache*gcno" -exec sh -c 'cp "$1" "$2/$(basename "$1").$3"' _ {} "$covdir" "$ts" \;
}


pcache_rmmod() {
    dump_gcov
    sudo rmmod dm-pcache 2>/dev/null || true
}

reset_gcov() {
    echo 1 | sudo tee /sys/kernel/debug/gcov/reset >/dev/null
}

pcache_insmod() {
    reset_gcov
    sudo insmod "$1"
}


# Default paths if not provided by environment
: "${linux_path:=/workspace/linux_compile}"
: "${cache_dev0:=/dev/pmem0}"
: "${cache_dev1:=/dev/pmem1}"
: "${data_crc:=false}"
: "${gc_percent:=}"
: "${cache_mode:=writeback}"
: "${data_dev0:?data_dev0 not set}"
: "${data_dev1:?data_dev1 not set}"

dm_name0="pcache_$(basename "${data_dev0}")"
dm_name1="pcache_$(basename "${data_dev1}")"

# Remove any existing devices before reloading the module
sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true

# Verify cache mode support before running tests
pcache_rmmod
pcache_insmod "${linux_path}/drivers/md/dm-pcache/dm-pcache.ko"
dd if=/dev/zero of="${cache_dev0}" bs=1M count=1 oflag=direct
dd if=/dev/zero of="${cache_dev1}" bs=1M count=1 oflag=direct
SEC_NR=$(sudo blockdev --getsz "${data_dev0}")
if ! sudo dmsetup create "${dm_name0}_probe" --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove "${dm_name0}_probe"

: "${TEST_MNT:=/mnt/test}"
: "${SCRATCH_MNT:=/mnt/scratch}"

cleanup() {
    sudo umount "${TEST_MNT}" 2>/dev/null || true
    sudo umount "${SCRATCH_MNT}" 2>/dev/null || true
    sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
    sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
    pcache_rmmod
}
trap cleanup EXIT

# Prepare pcache devices
bash ./pcache.py.data/pcache.sh

# Mount points for xfstests
sudo mkdir -p "${TEST_MNT}" "${SCRATCH_MNT}"

# Run a basic xfstests case
cd /workspace/xfstests
./check -g generic/rw -E ./exclude.exclude
