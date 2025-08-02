#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"
: "${cache_dev0:=/dev/pmem0}"
: "${data_dev0:?data_dev0 not set}"
: "${data_dev1:?data_dev1 not set}"
: "${cache_mode:=writeback}"
: "${data_crc:=false}"

DM_NAME="pcache_$(basename "${data_dev0}")"
DM_NAME1="pcache_$(basename "${data_dev1}")"

reset_pmem() {
    dd if=/dev/zero of="${cache_dev0}" bs=1M count=1 oflag=direct
    sync
}

cleanup() {
    if [[ -n "${MAKE_FAIL_PATH}" ]]; then
        sudo sh -c "echo 0 > ${MAKE_FAIL_PATH}" 2>/dev/null || true
    fi
    sudo sh -c "echo 0 > /sys/kernel/debug/fail_make_request/times" 2>/dev/null || true
    sudo sh -c "echo 0 > /sys/kernel/debug/fail_make_request/verbose" 2>/dev/null || true
    sudo dmsetup remove "${DM_NAME}" 2>/dev/null || true
    sudo dmsetup remove "${DM_NAME1}" 2>/dev/null || true
    sudo rmmod dm-pcache 2>/dev/null || true

    [[ -n "${TMP_IN}" && -f "${TMP_IN}" ]] && rm -f "${TMP_IN}"
    [[ -n "${TMP_OUT}" && -f "${TMP_OUT}" ]] && rm -f "${TMP_OUT}"
}
trap cleanup EXIT

sudo dmsetup remove "${DM_NAME}" 2>/dev/null || true
sudo dmsetup remove "${DM_NAME1}" 2>/dev/null || true
sudo rmmod dm-pcache 2>/dev/null || true
sudo insmod "${linux_path}"/drivers/md/dm-pcache/dm-pcache.ko
reset_pmem
SEC_NR=$(sudo blockdev --getsz "${data_dev0}")
if ! sudo dmsetup create "${DM_NAME}"_probe --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"; then
    echo "cache_mode ${cache_mode} not supported, skipping"
    exit 0
fi
sudo dmsetup remove "${DM_NAME}"_probe
reset_pmem

SEC_NR=$(sudo blockdev --getsz "${data_dev0}")
sudo dmsetup create "${DM_NAME}" --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode ${cache_mode} data_crc ${data_crc}"

# configure fail_make_request on the backing device
sudo sh -c "echo 2 > /sys/kernel/debug/fail_make_request/interval"
sudo sh -c "echo 50 > /sys/kernel/debug/fail_make_request/probability"
sudo sh -c "echo 100 > /sys/kernel/debug/fail_make_request/times"
sudo sh -c "echo 1 > /sys/kernel/debug/fail_make_request/verbose"
MAJ_MIN=$(lsblk -d -no MAJ:MIN "${data_dev0}" | tr -d '[:space:]')
MAKE_FAIL_PATH="/sys/dev/block/${MAJ_MIN}/make-it-fail"
if [[ ! -e "${MAKE_FAIL_PATH}" ]]; then
    MAKE_FAIL_PATH="/sys/block/$(basename "${data_dev0}")/make-it-fail"
    if [[ ! -e "${MAKE_FAIL_PATH}" ]]; then
        parent=$(lsblk -no pkname "${data_dev0}" | head -n 1 | tr -d '[:space:]')
        if [[ -n "${parent}" ]]; then
            MAKE_FAIL_PATH="/sys/block/${parent}/$(basename "${data_dev0}")/make-it-fail"
        fi
    fi
fi
sudo sh -c "echo 1 > ${MAKE_FAIL_PATH}"

# read should fail
if dd if=/dev/mapper/"${DM_NAME}" of=/dev/null bs=1M count=100 iflag=direct; then
    echo "read succeeded when fail_make_request is enabled"
    exit 1
fi

expect_write_success=false
if [[ "${cache_mode}" == "writeback" || "${cache_mode}" == "writeonly" ]]; then
    expect_write_success=true
fi

TMP_IN=$(mktemp)
dd if=/dev/urandom of="${TMP_IN}" bs=1M count=100

if dd if="${TMP_IN}" of=/dev/mapper/"${DM_NAME}" bs=1M count=100 oflag=direct; then
    [[ "${expect_write_success}" == true ]] || {
        echo "write unexpectedly succeeded for cache_mode ${cache_mode}"
        exit 1
    }

    TMP_OUT=$(mktemp)
    dd if=/dev/mapper/"${DM_NAME}" of="${TMP_OUT}" bs=1M count=100 iflag=direct
    orig_md5=$(md5sum "${TMP_IN}" | awk '{print $1}')
    new_md5=$(md5sum "${TMP_OUT}" | awk '{print $1}')
    if [[ "${orig_md5}" != "${new_md5}" ]]; then
        echo "md5 mismatch between written and read data"
        exit 1
    fi
else
    [[ "${expect_write_success}" != true ]] || {
        echo "write unexpectedly failed for cache_mode ${cache_mode}"
        exit 1
    }
fi
