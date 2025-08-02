#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"
: "${striped:=false}"
: "${cache_dev0:=/dev/pmem0}"
: "${cache_dev1:=/dev/pmem1}"
: "${data_crc:=false}"
: "${gc_percent:=}"
: "${data_dev0:?data_dev0 not set}"
: "${data_dev1:?data_dev1 not set}"
: "${cache_mode:=writeback}"

dm_name0="pcache_$(basename ${data_dev0})"
dm_name1="pcache_$(basename ${data_dev1})"

pmem_a=${cache_dev0}
pmem_b=${cache_dev1}
export pmem_a pmem_b

if [[ "${striped}" == "true" ]]; then
    sudo dmsetup remove striped1 2>/dev/null || true
    sudo dd if=/dev/zero of=${pmem_a} bs=1M count=16 oflag=direct
    sudo dd if=/dev/zero of=${pmem_b} bs=1M count=16 oflag=direct
    sudo dmsetup create striped1 --table "0 8388608 striped 2 8 ${pmem_a} 0 ${pmem_b} 0"
    cache_dev0=/dev/mapper/striped1
fi

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko
if [[ "${striped}" == "true" ]]; then
    dd if=/dev/zero of=${pmem_a} bs=1M count=1 oflag=direct
    dd if=/dev/zero of=${pmem_b} bs=1M count=1 oflag=direct
else
    dd if=/dev/zero of=${cache_dev0} bs=1M count=1 oflag=direct
fi
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
if ! sudo dmsetup create ${dm_name0}_probe --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove ${dm_name0}_probe

reset_pmem() {
    if [[ "${striped}" == "true" ]]; then
        dd if=/dev/zero of=${pmem_a} bs=1M count=1 oflag=direct
        dd if=/dev/zero of=${pmem_b} bs=1M count=1 oflag=direct
    else
        dd if=/dev/zero of=${cache_dev0} bs=1M count=1 oflag=direct
    fi
    sync
}

export linux_path cache_dev0 data_crc gc_percent data_dev0 data_dev1 cache_mode dm_name0 dm_name1
export -f reset_pmem

test_dir="$(dirname "$0")/pcache_misc_tests"

for tc in "$test_dir"/*.sh; do
    echo "===== Running $(basename "$tc") =====" | sudo tee /dev/kmsg
    bash "$tc"
    echo "===== Finished $(basename "$tc") =====" | sudo tee /dev/kmsg
done

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
