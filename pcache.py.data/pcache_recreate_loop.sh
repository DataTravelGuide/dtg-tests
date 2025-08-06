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

: "${linux_path:=/workspace/linux_compile}"
: "${cache_dev0:=/dev/pmem0}"
: "${data_dev0:?data_dev0 not set}"
: "${cache_mode:=writeback}"
: "${data_crc:=false}"
: "${iterations:=50}"

dm_name="pcache_$(basename ${data_dev0})"

sudo dmsetup remove "${dm_name}" 2>/dev/null || true
pcache_rmmod
pcache_insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko

dd if=/dev/zero of=${cache_dev0} bs=1M count=1 oflag=direct

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
for i in $(seq 1 ${iterations}); do
    sudo dmsetup create "${dm_name}" --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
    fio --name=pcache_stress --filename=/dev/mapper/${dm_name} --ioengine=libaio --direct=1 --bs=4k --rw=write --runtime=10 --time_based=1 --iodepth=16 --numjobs=1 --group_reporting
    sudo dmsetup remove "${dm_name}"
    sync
    echo "Completed iteration $i" | sudo tee /dev/kmsg
    sleep 1

done

pcache_rmmod
