#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"

cd "${linux_path}"

for file in $(git ls-files drivers/md/dm-pcache/); do
    ./scripts/checkpatch.pl --fix-inplace "$file"
    if [[ $? -ne 0 ]]; then
        echo "checkpatch failed for $file"
        exit 1
    fi
done

