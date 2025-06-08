#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"
: "${cache_dev0:=/dev/pmem0}"
: "${data_crc:=false}"
: "${gc_percent:=}"
: "${data_dev0:?data_dev0 not set}"

dm_name0="pcache_$(basename ${data_dev0})"

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true

sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko



dd if=/dev/zero of=${cache_dev0} bs=1M count=1

SEC_NR=$(sudo blockdev --getsz ${data_dev0})

# Expect dmsetup create to fail with an invalid cache mode
if echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} invalid ${data_crc}" | \
    sudo dmsetup create pcache_invalid; then
    echo "dmsetup create succeeded with invalid cache_mode"
    sudo dmsetup remove pcache_invalid
    exit 1
fi

# Expect dmsetup create to fail with an invalid data_crc value
if echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback invalid" | \
    sudo dmsetup create pcache_invalid; then
    echo "dmsetup create succeeded with invalid data_crc"
    sudo dmsetup remove pcache_invalid
    exit 1
fi


# Expect dmsetup create to fail if cache_mode is empty
if echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0}  ${data_crc}" | \
    sudo dmsetup create pcache_invalid; then
    echo "dmsetup create succeeded with empty cache_mode"
    sudo dmsetup remove pcache_invalid
    exit 1
fi

# Expect dmsetup create to fail if data_crc is empty
if echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback " | \
    sudo dmsetup create pcache_invalid; then
    echo "dmsetup create succeeded with empty data_crc"
    sudo dmsetup remove pcache_invalid
    exit 1
fi

echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${data_crc}" | sudo dmsetup create ${dm_name0}

# gc_percent message sanity checks
if sudo dmsetup message ${dm_name0} 0 gc_percent 91; then
    echo "dmsetup message succeeded with gc_percent > 90"
    exit 1
fi

if sudo dmsetup message ${dm_name0} 0 gc_percent -1; then
    echo "dmsetup message succeeded with negative gc_percent"
    exit 1
fi

if sudo dmsetup message ${dm_name0} 0 gc_percent ""; then
    echo "dmsetup message succeeded with empty gc_percent"
    exit 1
fi

if sudo dmsetup message ${dm_name0} 0 gc_percent bad; then
    echo "dmsetup message succeeded with string gc_percent"
    exit 1
fi

if [[ -n "${gc_percent}" ]]; then
    sudo dmsetup message ${dm_name0} 0 gc_percent ${gc_percent}
fi

# Expect dmsetup message to fail with an unknown command
if sudo dmsetup message ${dm_name0} 0 invalid_cmd 1; then
    echo "dmsetup message succeeded with unknown command"
    exit 1
fi

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

dd if=/dev/urandom of=/mnt/pcache/testfile bs=1M count=10
orig_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')
sudo umount /mnt/pcache

sudo dmsetup remove ${dm_name0}

echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${data_crc}" | sudo dmsetup create ${dm_name0}
sudo mount /dev/mapper/${dm_name0} /mnt/pcache
new_md5=$(md5sum /mnt/pcache/testfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after recreate"
    exit 1
fi
sudo umount /mnt/pcache

fio --name=pcachetest --filename=/dev/mapper/${dm_name0} --rw=randwrite --bs=4k --runtime=10 --time_based=1 --ioengine=libaio --direct=1 &
fio_pid=$!
sleep 2
sudo dmsetup remove --force ${dm_name0} || true
wait ${fio_pid} || true

sudo dmsetup remove ${dm_name0} 2>/dev/null || true

# Attempt to recreate with a different data_crc value and expect failure
if [[ "${data_crc}" == "true" ]]; then
    new_crc=false
else
    new_crc=true
fi
if echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${new_crc}" | \
    sudo dmsetup create ${dm_name0}; then
    echo "dmsetup create succeeded after data_crc change"
    sudo dmsetup remove ${dm_name0}
    exit 1
fi

sudo rmmod dm-pcache 2>/dev/null || true

# Scenario: flush cached data and verify persistence after removing pcache
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko


dd if=/dev/zero of=${cache_dev0} bs=1M count=1

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${data_crc}" | sudo dmsetup create ${dm_name0}

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

# Record pcache status once the cache is flushed
status_before_remove=$(sudo dmsetup status ${dm_name0})
read -ra status_fields <<< "$status_before_remove"
status_before_len=${#status_fields[@]}
before_key_head=${status_fields[$((status_before_len - 3))]}
before_dirty_tail=${status_fields[$((status_before_len - 2))]}
before_key_tail=${status_fields[$((status_before_len - 1))]}

sudo dmsetup remove ${dm_name0}

echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${data_crc}" | sudo dmsetup create ${dm_name0}
# Suspend the newly created pcache device and ensure reload fails
sudo dmsetup suspend ${dm_name0}
if echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${data_crc}" | sudo dmsetup reload ${dm_name0}; then
    echo "dmsetup reload unexpectedly succeeded"
    exit 1
fi
sudo dmsetup resume ${dm_name0}
# Capture status after recreating pcache
status_after_create=$(sudo dmsetup status ${dm_name0})
read -ra status_fields <<< "$status_after_create"
status_after_len=${#status_fields[@]}
after_key_head=${status_fields[$((status_after_len - 3))]}
after_dirty_tail=${status_fields[$((status_after_len - 2))]}
after_key_tail=${status_fields[$((status_after_len - 1))]}
# Verify key fields match after recreation
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

dd if=/dev/zero of=${cache_dev0} bs=1M count=10

echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${data_crc}" | sudo dmsetup create ${dm_name0}
sudo mount /dev/mapper/${dm_name0} /mnt/pcache
new_md5=$(md5sum /mnt/pcache/persistfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after recreating pcache"
    exit 1
fi
sudo umount /mnt/pcache

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true

# Scenario: verify data consistency under heavy IO load
sudo insmod ${linux_path}/drivers/md/dm-pcache/dm-pcache.ko

dd if=/dev/zero of=${cache_dev0} bs=1M count=1

SEC_NR=$(sudo blockdev --getsz ${data_dev0})
echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${data_crc}" | sudo dmsetup create ${dm_name0}

sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
sudo mkdir -p /mnt/pcache
sudo mount /dev/mapper/${dm_name0} /mnt/pcache

dd if=/dev/urandom of=/mnt/pcache/heavyfile bs=1M count=50
orig_md5=$(md5sum /mnt/pcache/heavyfile | awk '{print $1}')

if [[ -n "${gc_percent}" ]]; then
    sudo dmsetup message ${dm_name0} 0 gc_percent ${gc_percent}
fi

# Copy heavyfile to loadfile and verify checksum
dd if=/mnt/pcache/heavyfile of=/mnt/pcache/loadfile bs=4k oflag=direct iflag=fullblock
new_md5=$(md5sum /mnt/pcache/loadfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after copy"
    exit 1
fi

# Stress the device with fio using libaio
fio --name=pcacheheavy --ioengine=libaio \
    --filename=/mnt/pcache/stressfile --rw=randwrite --size=100m \
    --runtime=20 --time_based=1 --bs=4k --direct=1 \
    --numjobs=4 --iodepth=16

new_md5=$(md5sum /mnt/pcache/loadfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after heavy IO"
    exit 1
fi

sync
sudo umount /mnt/pcache
sudo dmsetup remove ${dm_name0}

echo "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} writeback ${data_crc}" | sudo dmsetup create ${dm_name0}
sudo mount /dev/mapper/${dm_name0} /mnt/pcache
new_md5=$(md5sum /mnt/pcache/heavyfile | awk '{print $1}')
if [[ "${orig_md5}" != "${new_md5}" ]]; then
    echo "MD5 mismatch after heavy IO"
    exit 1
fi
sudo umount /mnt/pcache

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
