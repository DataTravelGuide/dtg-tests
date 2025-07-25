#!/bin/bash
set -ex
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko 2>/dev/null || true
: "${cache_mode:=writeback}"
reset_pmem

if [[ "${cache_mode}" != "writeonly" ]]; then
    echo "cache_mode is ${cache_mode}, skipping writeonly test"
    exit 0
fi
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
if ! sudo dmsetup create ${dm_name0}_probe --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove ${dm_name0}_probe
reset_pmem


echo "DEBUG: case 18 - verify writeonly mode behavior"

src_file="$(dirname "$0")/writeonly_source.bin"
read_file="$(dirname "$0")/writeonly_read.bin"

dd if=/dev/urandom of="${src_file}" bs=1M count=10
orig_md5=$(md5sum "${src_file}" | awk '{print $1}')

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

dd if="${src_file}" of=/dev/mapper/${dm_name0} bs=1M
sync

sudo dmsetup message ${dm_name0} 0 gc_percent 0
while true; do
    status=$(sudo dmsetup status ${dm_name0})
    read -ra fields <<< "$status"
    len=${#fields[@]}
    key_head=${fields[$((len - 3))]}
    key_tail=${fields[$((len - 1))]}
    if [[ "$key_head" == "$key_tail" ]]; then
        break
    fi
    sleep 1
done

sudo dmsetup remove ${dm_name0}

sudo dd if=/dev/zero of=${cache_dev0} bs=1M count=1

sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

dd if=/dev/mapper/${dm_name0} of="${read_file}" bs=1M count=10
new_md5=$(md5sum "${read_file}" | awk '{print $1}')

status=$(sudo dmsetup status ${dm_name0})
read -ra fields <<< "$status"
len=${#fields[@]}
key_head=${fields[$((len - 3))]}

if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after recreating pcache"
    exit 1
fi

if [[ "${key_head}" != "0:0" ]]; then
    echo "key_head is ${key_head}, expected 0:0"
    exit 1
fi

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rm -f "${src_file}" "${read_file}"
sudo rmmod dm-pcache 2>/dev/null || true

