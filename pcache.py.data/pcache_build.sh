#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"
: "${kernel_dir_32:=/workspace_data/linux_compile_32/}"

pushd "$linux_path"
cleanup() {
    popd
}
trap cleanup EXIT

make clean M=drivers/md/dm-pcache
make C=1 M=drivers/md/dm-pcache
make clean M=drivers/md/dm-pcache
make M=drivers/md/dm-pcache/  C=2 CHECK="/workspace/smatch/smatch -p=kernel --full-path" -j 32 2>&1 | tee smatch.out
grep -Ei 'warn|error' smatch.out && exit 1
make htmldocs SPHINXDIRS=admin-guide/device-mapper SPHINXOPTS="-W -n -j1 --keep-going -D suppress_warnings=ref.doc"

if [ -d "$kernel_dir_32" ]; then
    pushd "$kernel_dir_32"
    make clean M=drivers/md/dm-pcache/
    make -j 64 ARCH=i386 M=drivers/md/dm-pcache/
    popd
else
    echo "kernel_dir_32 not found ($kernel_dir_32), skipping 32-bit build."
fi

