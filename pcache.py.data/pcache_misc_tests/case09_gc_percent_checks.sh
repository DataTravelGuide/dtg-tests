#!/bin/bash
set -e
reset_pmem
SEC_NR=$(sudo blockdev --getsz ${data_dev0})

echo "DEBUG: case 9 - basic create and gc_percent message checks"
sudo dmsetup create ${dm_name0} --table "0 ${SEC_NR} pcache ${cache_dev0} ${data_dev0} 4 cache_mode writeback data_crc ${data_crc}"

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
