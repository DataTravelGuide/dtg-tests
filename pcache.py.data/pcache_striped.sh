#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"
: "${cache_dev0:=/dev/pmem0}"
: "${cache_dev1:=/dev/pmem1}"
: "${cache_dev2:=/dev/pmem2}"
: "${cache_dev3:=/dev/pmem3}"
: "${data_crc:=false}"
: "${gc_percent:=}"
: "${cache_mode:=writeback}"
: "${data_dev0:?data_dev0 not set}"
: "${data_dev1:?data_dev1 not set}"

stripe0="striped1"
stripe1="striped2"
dm_name0="pcache_$(basename ${data_dev0})"
dm_name1="pcache_$(basename ${data_dev1})"

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
sudo dmsetup remove "${stripe0}" 2>/dev/null || true
sudo dmsetup remove "${stripe1}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true

sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko

sudo dd if=/dev/zero of=${cache_dev0} bs=1M count=16 oflag=direct
sudo dd if=/dev/zero of=${cache_dev1} bs=1M count=16 oflag=direct
sudo dd if=/dev/zero of=${cache_dev2} bs=1M count=16 oflag=direct
sudo dd if=/dev/zero of=${cache_dev3} bs=1M count=16 oflag=direct

sudo dmsetup create ${stripe0} --table "0 8388608 striped 2 8 ${cache_dev0} 0 ${cache_dev1} 0"
sudo dmsetup create ${stripe1} --table "0 8388608 striped 2 8 ${cache_dev2} 0 ${cache_dev3} 0"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create "${dm_name0}" --table "0 ${SEC_NR} pcache /dev/mapper/${stripe0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
SEC_NR=$(sudo blockdev --getsz ${data_dev1})
sudo dmsetup create "${dm_name1}" --table "0 ${SEC_NR} pcache /dev/mapper/${stripe1} ${data_dev1} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

if [[ -n "${gc_percent}" ]]; then
    sudo dmsetup message "${dm_name0}" 0 gc_percent ${gc_percent}
    sudo dmsetup message "${dm_name1}" 0 gc_percent ${gc_percent}
fi

sudo mkfs.xfs -f /dev/mapper/${dm_name0}
