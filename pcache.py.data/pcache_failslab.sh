#!/bin/bash
set -euxo pipefail

# Default parameters if not provided by environment
: "${linux_path:=/workspace/linux_compile}"
: "${cache_dev0:=/dev/pmem0}"
: "${data_dev0:?data_dev0 not set}"
: "${cache_mode:=writeback}"
: "${data_crc:=false}"

dm_name0="pcache_$(basename "${data_dev0}")"
dm_name1="pcache_$(basename "${data_dev1}")"

# Ensure any leftover device is cleaned up before reloading the module
sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true

# Check whether the requested cache mode is supported. If not, skip the test
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod "${linux_path}/drivers/md/dm-pcache/dm-pcache.ko"
dd if=/dev/zero of="${cache_dev0}" bs=1M count=1 oflag=direct
SEC_NR=$(sudo blockdev --getsz "${data_dev0}")
if ! sudo dmsetup create "${dm_name0}_probe" --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove "${dm_name0}_probe"

DBG=/sys/kernel/debug/failslab
PROB=50
INTERVAL=10
TIMES=100
VERBOSE=1

cleanup() {
    echo 0 > "$DBG/times" || true
}
trap cleanup EXIT

# Configure failslab
sudo sh -c "echo $PROB > $DBG/probability"
sudo sh -c "echo $INTERVAL > $DBG/interval"
sudo sh -c "echo $VERBOSE > $DBG/verbose"
sudo sh -c "echo Y > $DBG/cache-filter"
sudo sh -c "echo N > $DBG/ignore-gfp-wait"
sudo sh -c "echo $TIMES > $DBG/times"

# Prepare pcache devices
bash ./pcache.py.data/pcache.sh

# Enable failslab for pcache slabs
sudo sh -c 'echo 1 > /sys/kernel/slab/pcache_cache_key/failslab'
sudo sh -c 'echo 1 > /sys/kernel/slab/pcache_backing_dev_req/failslab'

cd /workspace/xfstests/
# Run single xfstests case that triggers pcache creation
sudo ./check generic/001

echo "==> Done. See dmesg for failslab traces."
