#!/bin/bash
set -ex

: "${teafs_path:?teafs_path is required}"
: "${linux_path:=}"

pushd "${teafs_path}"
cleanup() {
    popd
}
trap cleanup EXIT

make clean

if [ -n "$smatch" ]; then
    make C=2 CHECK="/workspace/smatch/smatch -p=kernel --full-path" -j 32 2>&1 | tee smatch.out
    grep -Ei 'warn|error' smatch.out && exit 1
else
    make
fi

echo "OK"
