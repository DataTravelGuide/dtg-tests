#!/bin/bash
set -ex
sudo dmsetup remove "${dm_name0}" 2>/dev/null || true
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

echo "DEBUG: case 20 - simulate backing_dev IO error with fail_make_request"
SEC_NR=$(sudo blockdev --getsz ${data_dev0})
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

# configure fail_make_request on the backing device
sudo sh -c "echo 2 > /sys/kernel/debug/fail_make_request/interval"
sudo sh -c "echo 50 > /sys/kernel/debug/fail_make_request/probability"
sudo sh -c "echo 100 > /sys/kernel/debug/fail_make_request/times"
sudo sh -c "echo 1 > /sys/kernel/debug/fail_make_request/verbose"
MAKE_FAIL_PATH="/sys/block/$(basename ${data_dev0})/make-it-fail"
if [[ ! -e ${MAKE_FAIL_PATH} ]]; then
    parent=$(lsblk -no pkname ${data_dev0})
    MAKE_FAIL_PATH="/sys/block/${parent}/$(basename ${data_dev0})/make-it-fail"
fi
sudo sh -c "echo 1 > ${MAKE_FAIL_PATH}"

# read should fail when backing device returns errors
if dd if=/dev/mapper/${dm_name0} of=/dev/null bs=4k count=1 iflag=direct; then
    echo "read succeeded when fail_make_request is enabled"
    sudo sh -c "echo 0 > ${MAKE_FAIL_PATH}"
    sudo dmsetup remove ${dm_name0}
    exit 1
fi

# determine expected outcome of writes
expect_write_success=false
if [[ "${cache_mode}" == "writeback" || "${cache_mode}" == "writeonly" ]]; then
    expect_write_success=true
fi

# attempt a write through pcache
if dd if=/dev/zero of=/dev/mapper/${dm_name0} bs=4k count=1 oflag=direct; then
    if [[ "${expect_write_success}" != true ]]; then
        echo "write unexpectedly succeeded for cache_mode ${cache_mode}"
        sudo sh -c "echo 0 > ${MAKE_FAIL_PATH}"
        sudo sh -c "echo 0 > /sys/kernel/debug/fail_make_request/times"
        sudo sh -c "echo 0 > /sys/kernel/debug/fail_make_request/verbose"
        sudo dmsetup remove ${dm_name0}
        exit 1
    fi
else
    if [[ "${expect_write_success}" == true ]]; then
        echo "write unexpectedly failed for cache_mode ${cache_mode}"
        sudo sh -c "echo 0 > ${MAKE_FAIL_PATH}"
        sudo sh -c "echo 0 > /sys/kernel/debug/fail_make_request/times"
        sudo sh -c "echo 0 > /sys/kernel/debug/fail_make_request/verbose"
        sudo dmsetup remove ${dm_name0}
        exit 1
    fi
fi

sudo sh -c "echo 0 > ${MAKE_FAIL_PATH}"
sudo sh -c "echo 0 > /sys/kernel/debug/fail_make_request/times"
sudo sh -c "echo 0 > /sys/kernel/debug/fail_make_request/verbose"

sudo dmsetup remove ${dm_name0} 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
