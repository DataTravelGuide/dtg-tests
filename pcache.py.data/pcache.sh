#!/bin/bash
set -ex

# Default values
: "${data_crc:=false}"
: "${gc_percent:=}"
: "${data_dev0:=/dev/ram0p1}"
: "${data_dev1:=/dev/ram0p2}"

# Remove existing device-mapper targets if they exist
sudo dmsetup remove pcache_ram0p1 2>/dev/null || true
sudo dmsetup remove pcache_ram0p2 2>/dev/null || true

# Unload modules if already loaded
sudo rmmod dm-pcache 2>/dev/null || true

# Load required modules
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko


dd if=/dev/zero of=/dev/pmem0 bs=1M count=1
dd if=/dev/zero of=/dev/pmem1 bs=1M count=1

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${data_crc}" | sudo dmsetup create pcache_ram0p1
SEC_NR=$(sudo blockdev --getsz ${data_dev1})
echo "0 ${SEC_NR} pcache ${cache_dev1} ${data_dev1} writeback ${data_crc}" | sudo dmsetup create pcache_ram0p2

# Tune GC threshold if provided
if [[ -n "${gc_percent}" ]]; then
    sudo dmsetup message pcache_ram0p1 0 gc_percent ${gc_percent}
    sudo dmsetup message pcache_ram0p2 0 gc_percent ${gc_percent}
fi

sudo mkfs.xfs -f /dev/mapper/pcache_ram0p1
