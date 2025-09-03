#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"

cd "${linux_path}"

need_pop=0
if [ -n "$(git status --porcelain)" ]; then
    git stash -q
    need_pop=1
fi
trap '[ "$need_pop" -eq 1 ] && git stash pop -q' EXIT

for file in $(git ls-files drivers/md/dm-pcache/); do
    ./scripts/checkpatch.pl --fix-inplace "$file"
    if [[ $? -ne 0 ]]; then
        echo "checkpatch failed for $file"
        exit 1
    fi
done

