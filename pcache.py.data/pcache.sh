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


# Default values
: "${striped:=false}"
: "${data_crc:=false}"
: "${gc_percent:=}"
: "${cache_mode:=writeback}"
: "${data_dev0:?data_dev0 not set}"
: "${data_dev1:?data_dev1 not set}"

if [[ "${striped}" == "true" ]]; then
    bash "$(dirname "$0")/pcache_striped.sh"
    exit $?
fi

dm_name0="pcache_$(basename ${data_dev0})"
dm_name1="pcache_$(basename ${data_dev1})"

# Remove existing device-mapper targets if they exist
sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true

# Unload modules if already loaded
pcache_rmmod

# Load required modules
pcache_insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko
dd if=/dev/zero of=${cache_dev0} bs=1M count=1 oflag=direct
dd if=/dev/zero of=${cache_dev1} bs=1M count=1 oflag=direct
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
if ! sudo dmsetup create ${dm_name0}_probe --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove ${dm_name0}_probe

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create "${dm_name0}" --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
SEC_NR=$(sudo blockdev --getsz ${data_dev1})
sudo dmsetup create "${dm_name1}" --table "0 ${SEC_NR} pcache ${cache_dev1} ${data_dev1} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

# Tune GC threshold if provided
if [[ -n "${gc_percent}" ]]; then
    sudo dmsetup message "${dm_name0}" 0 gc_percent ${gc_percent}
    sudo dmsetup message "${dm_name1}" 0 gc_percent ${gc_percent}
fi

sudo mkfs.xfs -f /dev/mapper/${dm_name0}
