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
PROB=95
INTERVAL=1
TIMES=1000
VERBOSE=1

configure_failslab() {
    sudo sh -c "echo $PROB > $DBG/probability"
    sudo sh -c "echo $INTERVAL > $DBG/interval"
    sudo sh -c "echo $VERBOSE > $DBG/verbose"
    sudo sh -c "echo Y > $DBG/cache-filter"
    sudo sh -c "echo N > $DBG/ignore-gfp-wait"
    sudo sh -c "echo $TIMES > $DBG/times"
}

reset_failslab() {
    sudo sh -c "echo 0 > $DBG/probability"
    sudo sh -c "echo 0 > $DBG/interval"
    sudo sh -c "echo 0 > $DBG/verbose"
    sudo sh -c "echo N > $DBG/cache-filter"
    sudo sh -c "echo Y > $DBG/ignore-gfp-wait"
    sudo sh -c "echo 0 > $DBG/times"
    sudo sh -c 'echo 0 > /sys/kernel/slab/pcache_cache_key/failslab'
    sudo sh -c 'echo 0 > /sys/kernel/slab/pcache_backing_dev_req/failslab'
}

cleanup() {
    echo 0 > "$DBG/times" || true
}
trap cleanup EXIT

# Configure failslab
configure_failslab

# Prepare pcache devices
bash ./pcache.py.data/pcache.sh

# Enable failslab for pcache slabs
sudo sh -c 'echo 1 > /sys/kernel/slab/pcache_cache_key/failslab'
sudo sh -c 'echo 1 > /sys/kernel/slab/pcache_backing_dev_req/failslab'

# Run fio workload to trigger pcache slab allocations
fio --name=pcache_failslab --filename=/dev/mapper/pcache_ram0p1 --ioengine libaio --rw=randread --bs=4k --numjobs=16 --iodepth=16 --direct=1 --size=1G

# Reset failslab parameters before running randwrite workload
reset_failslab
configure_failslab
sudo sh -c 'echo 1 > /sys/kernel/slab/pcache_cache_key/failslab'
sudo sh -c 'echo 1 > /sys/kernel/slab/pcache_backing_dev_req/failslab'

fio --name=pcache_failslab_write --filename=/dev/mapper/pcache_ram0p1 --ioengine libaio --rw=randwrite --bs=4k --numjobs=16 --iodepth=16 --direct=1 --size=1G

echo "==> Done. See dmesg for failslab traces."
