#!/bin/bash
set -e
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko 2>/dev/null || true
: "${cache_mode:=writeback}"
reset_pmem

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
if ! sudo dmsetup create ${dm_name0}_probe --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove ${dm_name0}_probe
reset_pmem

echo "DEBUG: case 13 - flush cached data and verify persistence"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

dd if=/dev/urandom of=/mnt/pcache/persistfile bs=1M count=5
orig_md5=$(md5sum /mnt/pcache/persistfile | awk '{print $1}')
sudo umount /mnt/pcache

sudo dmsetup message ${dm_name0} 0 gc_percent 0

while true; do
    status=$(sudo dmsetup status ${dm_name0})
    read -ra fields <<< "$status"
    len=${#fields[@]}
    key_head=${fields[$((len - 3))]}
    dirty_tail=${fields[$((len - 2))]}
    key_tail=${fields[$((len - 1))]}
    if [[ "$key_head" == "$key_tail" ]]; then
        break
    fi
    sleep 1
done

status_before_remove=$(sudo dmsetup status ${dm_name0})
read -ra status_fields <<< "$status_before_remove"
status_before_len=${#status_fields[@]}
before_key_head=${status_fields[$((status_before_len - 3))]}
before_dirty_tail=${status_fields[$((status_before_len - 2))]}
before_key_tail=${status_fields[$((status_before_len - 1))]}

sudo dmsetup remove ${dm_name0}

sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
sudo dmsetup suspend ${dm_name0}
if sudo dmsetup reload ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "dmsetup reload unexpectedly succeeded"
    exit 1
fi
sudo dmsetup resume ${dm_name0}
status_after_create=$(sudo dmsetup status ${dm_name0})
read -ra status_fields <<< "$status_after_create"
status_after_len=${#status_fields[@]}
after_key_head=${status_fields[$((status_after_len - 3))]}
after_dirty_tail=${status_fields[$((status_after_len - 2))]}
after_key_tail=${status_fields[$((status_after_len - 1))]}
if [[ "${before_key_head}" != "${after_key_head}" ||
      "${before_dirty_tail}" != "${after_dirty_tail}" ||
      "${before_key_tail}" != "${after_key_tail}" ]]; then
    echo "pcache status mismatch after recreate"
    exit 1
fi

sudo dmsetup remove ${dm_name0}

sudo mount ${data_dev0} /mnt/pcache
new_md5=$(md5sum /mnt/pcache/persistfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after removing pcache"
    exit 1
fi
sudo umount /mnt/pcache

reset_pmem

sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"
sudo mount /dev/mapper/${dm_name0} /mnt/pcache
new_md5=$(md5sum /mnt/pcache/persistfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after recreating pcache"
    exit 1
fi
sudo umount /mnt/pcache

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
