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
: "${iterations:=10}"

dm_name="pcache_$(basename ${data_dev0})"

sudo dmsetup remove "${dm_name}" 2>/dev/null || true
pcache_rmmod
pcache_insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko

dd if=/dev/zero of=${cache_dev0} bs=1M count=1 oflag=direct

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
if ! sudo dmsetup create "${dm_name}_probe" --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove "${dm_name}_probe"

dmesg_line=$(sudo dmesg | wc -l)
for i in $(seq 1 ${iterations}); do
    sudo dmsetup create "${dm_name}" --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
    fio --name=pcache_stress --filename=/dev/mapper/${dm_name} --ioengine=libaio --direct=1 --bs=128k --rw=randread --runtime=10 --time_based=1 --iodepth=64 --numjobs=4 --group_reporting &
    fio --name=pcache_stress --filename=/dev/mapper/${dm_name} --ioengine=libaio --direct=1 --bs=4k --rw=randwrite --runtime=10 --time_based=1 --iodepth=64 --numjobs=2 --group_reporting &
    fio --name=pcache_stress --filename=/dev/mapper/${dm_name} --ioengine=libaio --direct=1 --bs=256k --rw=randwrite --runtime=10 --time_based=1 --iodepth=64 --numjobs=2 --group_reporting &
    sleep 5
    sudo dmsetup remove "${dm_name}" --force || true
    sudo dmsetup remove "${dm_name}" --force || true
    sync
    new_dmesg_line=$(sudo dmesg | wc -l)
    if sudo dmesg | tail -n $((new_dmesg_line - dmesg_line)) | grep -Ei "Call Trace|BUG|WARNING"; then
        echo "Kernel log contains call trace or warnings" >&2
        exit 1
    fi
    dmesg_line=$new_dmesg_line
    echo "Completed iteration $i" | sudo tee /dev/kmsg
    dmesg_line=$((dmesg_line + 1))
    sleep 1

done

pcache_rmmod
new_dmesg_line=$(sudo dmesg | wc -l)
if sudo dmesg | tail -n $((new_dmesg_line - dmesg_line)) | grep -Ei "Call Trace|BUG|WARNING"; then
    echo "Kernel log contains call trace or warnings after rmmod" >&2
    exit 1
fi
