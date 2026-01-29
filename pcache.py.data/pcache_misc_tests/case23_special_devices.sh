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

if [[ "${cache_mode}" != "writeback" && "${cache_mode}" != "writethrough" ]]; then
    echo "cache_mode is ${cache_mode}, skipping special devices test for writeback/writethrough only"
    exit 0
fi

echo "DEBUG: case 23 - special device types behavior"

SEC_NR=$(sudo blockdev --getsz ${data_dev0})

# Test 1: RAM disk as cache device
echo "Testing ramdisk as cache device..."
RAMDISK_SIZE=8192  # 4MB ramdisk
sudo modprobe brd rd_nr=1 rd_size=${RAMDISK_SIZE}
sleep 1

if [[ -b /dev/ram0 ]]; then
    sudo dd if=/dev/zero of=/dev/ram0 bs=1M count=1 oflag=direct

    if sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache /dev/ram0 ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
        echo "Ramdisk cache creation succeeded"

        # Basic functionality test
        sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
        sudo mkdir -p /mnt/pcache
        sudo mount /dev/mapper/${dm_name0} /mnt/pcache

        echo "ramdisk test" | sudo tee /mnt/pcache/testfile >/dev/null
        content=$(cat /mnt/pcache/testfile)
        if [[ "${content}" != "ramdisk test" ]]; then
            echo "Ramdisk cache basic test failed"
            exit 1
        fi

        sudo umount /mnt/pcache
        sudo dmsetup remove ${dm_name0}
    else
        echo "Ramdisk cache creation failed"
    fi

    sudo modprobe -r brd
else
    echo "Ramdisk device not available, skipping ramdisk test"
fi

# Test 2: Loopback device with small file as cache
echo "Testing loopback device with small file as cache..."
LOOP_FILE="/tmp/cache_loop.img"
LOOP_SIZE=2048  # 1MB file
dd if=/dev/zero of="${LOOP_FILE}" bs=1K count=${LOOP_SIZE}
LOOP_DEV=$(sudo losetup --find --show "${LOOP_FILE}")

if [[ -n "${LOOP_DEV}" ]]; then
    if sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${LOOP_DEV} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
        echo "Loopback cache creation succeeded"

        # Basic functionality test
        sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
        sudo mount /dev/mapper/${dm_name0} /mnt/pcache

        echo "loopback test" | sudo tee /mnt/pcache/testfile >/dev/null
        content=$(cat /mnt/pcache/testfile)
        if [[ "${content}" != "loopback test" ]]; then
            echo "Loopback cache basic test failed"
            exit 1
        fi

        sudo umount /mnt/pcache
        sudo dmsetup remove ${dm_name0}
    else
        echo "Loopback cache creation failed"
    fi

    sudo losetup -d "${LOOP_DEV}"
    rm -f "${LOOP_FILE}"
else
    echo "Loopback device creation failed, skipping loopback test"
fi

# Test 3: ZRAM device as cache (if available)
echo "Testing zram as cache device..."
if sudo modprobe zram && [[ -b /dev/zram0 ]]; then
    echo "1024" | sudo tee /sys/block/zram0/disksize >/dev/null  # 1MB

    if sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache /dev/zram0 ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
        echo "ZRAM cache creation succeeded"

        # Basic functionality test
        sudo mkfs.ext4 -F /dev/mapper/${dm_name0}
        sudo mount /dev/mapper/${dm_name0} /mnt/pcache

        echo "zram test" | sudo tee /mnt/pcache/testfile >/dev/null
        content=$(cat /mnt/pcache/testfile)
        if [[ "${content}" != "zram test" ]]; then
            echo "ZRAM cache basic test failed"
            exit 1
        fi

        sudo umount /mnt/pcache
        sudo dmsetup remove ${dm_name0}
    else
        echo "ZRAM cache creation failed"
    fi

    sudo modprobe -r zram
else
    echo "ZRAM not available, skipping zram test"
fi

echo "Special devices test completed successfully"

sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
sudo dmsetup remove "${dm_name1}" 2>/dev/null || true
pcache_rmmod