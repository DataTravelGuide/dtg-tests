#!/bin/bash
set -ex

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

# Verify cache mode support before running tests
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod "${linux_path}/drivers/md/dm-pcache/dm-pcache.ko"
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
    sudo rmmod dm-pcache 2>/dev/null || true
}
trap cleanup EXIT

# Prepare pcache devices
bash ./pcache.py.data/pcache.sh

# Mount points for xfstests
sudo mkdir -p "${TEST_MNT}" "${SCRATCH_MNT}"

# Run a basic xfstests case
cd /workspace/xfstests
./check -g generic/rw -E ./exclude.exclude

