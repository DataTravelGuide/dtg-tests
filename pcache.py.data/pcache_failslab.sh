#!/bin/bash
set -euxo pipefail

DBG=/sys/kernel/debug/failslab
PROB=50
INTERVAL=10
TIMES=100
VERBOSE=1

cleanup() {
    echo 0 > "$DBG/times" || true
}
trap cleanup EXIT

# Configure failslab
sudo sh -c "echo $PROB > $DBG/probability"
sudo sh -c "echo $INTERVAL > $DBG/interval"
sudo sh -c "echo $VERBOSE > $DBG/verbose"
sudo sh -c "echo Y > $DBG/cache-filter"
sudo sh -c "echo N > $DBG/ignore-gfp-wait"
sudo sh -c "echo $TIMES > $DBG/times"

# Prepare pcache devices
bash ./pcache.py.data/pcache.sh

# Enable failslab for pcache slabs
sudo sh -c 'echo 1 > /sys/kernel/slab/pcache_cache_key/failslab'
sudo sh -c 'echo 1 > /sys/kernel/slab/pcache_backing_dev_req/failslab'

cd /workspace/xfstests/
# Run single xfstests case that triggers pcache creation
sudo ./check generic/001

echo "==> Done. See dmesg for failslab traces."
