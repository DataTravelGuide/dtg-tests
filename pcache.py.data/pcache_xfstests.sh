#!/bin/bash
set -ex

# Default paths if not provided by environment
: "${linux_path:=/workspace/linux_compile}"
: "${cache_dev0:=/dev/pmem0}"
: "${cache_dev1:=/dev/pmem1}"
: "${data_crc:=false}"
: "${gc_percent:=}"
: "${data_dev0:?data_dev0 not set}"
: "${data_dev1:?data_dev1 not set}"

dm_name0="pcache_$(basename ${data_dev0})"
dm_name1="pcache_$(basename ${data_dev1})"

: "${TEST_MNT:=/mnt/test}"
: "${SCRATCH_MNT:=/mnt/scratch}"

cleanup() {
    sudo umount "${TEST_MNT}" 2>/dev/null || true
    sudo umount "${SCRATCH_MNT}" 2>/dev/null || true
    sudo dmsetup remove ${dm_name0} 2>/dev/null || true
    sudo dmsetup remove ${dm_name1} 2>/dev/null || true
    sudo rmmod dm-pcache 2>/dev/null || true
}
trap cleanup EXIT

# Prepare pcache devices
bash ./pcache.py.data/pcache.sh

# Mount points for xfstests
sudo mkdir -p "${TEST_MNT}" "${SCRATCH_MNT}"

# Run a basic xfstests case
cd /workspace/xfstests
./check -g quick -g generic/rw -E ./exclude.exclude

