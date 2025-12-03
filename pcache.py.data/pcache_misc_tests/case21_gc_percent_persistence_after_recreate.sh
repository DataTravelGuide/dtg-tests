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

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
pcache_rmmod
pcache_insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko
: "${cache_mode:=writeback}"
reset_pmem

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
if ! sudo dmsetup create ${dm_name0}_probe --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove ${dm_name0}_probe
reset_pmem

GC_TARGET=10

sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

status_before=$(sudo dmsetup status ${dm_name0})
GC_BEFORE=$(echo "$status_before" | awk 'NR==1 {print $8}')
if [[ -z "$GC_BEFORE" ]]; then
    echo "status output missing gc_percent"
    exit 1
fi

sudo dmsetup message ${dm_name0} 0 gc_percent ${GC_TARGET}
status_updated=$(sudo dmsetup status ${dm_name0})
GC_UPDATED=$(echo "$status_updated" | awk 'NR==1 {print $8}')
if [[ "$GC_UPDATED" != "$GC_TARGET" ]]; then
    echo "gc_percent did not update to ${GC_TARGET}"
    exit 1
fi

sudo dmsetup remove ${dm_name0}

sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
status_recreated=$(sudo dmsetup status ${dm_name0})
GC_RECREATED=$(echo "$status_recreated" | awk 'NR==1 {print $8}')
if [[ "$GC_RECREATED" != "$GC_TARGET" ]]; then
    echo "gc_percent value not persisted after recreate"
    exit 1
fi

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
pcache_rmmod
