#!/bin/bash
set -ex

: "${covdir:=/workspace/datatravelguide/covdir}"

dump_gcov() {
    ts=$(date +%s)
    mkdir -p "$covdir"
    sudo find /sys/kernel/debug/gcov -path "*dm-pcache*gcda" -exec sh -c 'for f; do dest="$covdir/${f#/}.$ts"; mkdir -p "$(dirname "$dest")"; sudo cp "$f" "$dest"; done' sh {} +
    sudo find /sys/kernel/debug/gcov -path "*dm-pcache*gcno" -exec sh -c 'for f; do dest="$covdir/${f#/}.$ts"; mkdir -p "$(dirname "$dest")"; sudo cp "$f" "$dest"; done' sh {} +
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

echo "DEBUG: case 19 - verify dmsetup table output matches create parameters"

sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

cache_mm=$(lsblk -d -no MAJ:MIN ${cache_dev0} | tr -d ' ')
data_mm=$(lsblk -d -no MAJ:MIN ${data_dev0} | tr -d ' ')
expected="0 ${SEC_NR} pcache ${cache_mm} ${data_mm} 4 cache_mode ${cache_mode} crc ${data_crc}"

actual=$(sudo dmsetup table ${dm_name0})

if [[ "${actual}" != "${expected}" ]]; then
    echo "dmsetup table output mismatch"
    echo "Expected: ${expected}"
    echo "Actual:   ${actual}"
    sudo dmsetup remove ${dm_name0}
    exit 1
fi

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
pcache_rmmod
