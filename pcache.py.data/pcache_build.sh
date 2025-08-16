#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"

pushd "$linux_path"
cleanup() {
    popd
}
trap cleanup EXIT

make C=1 M=drivers/md/dm-pcache
make htmldocs SPHINXDIRS=admin-guide/device-mapper SPHINXOPTS="-W -n -j1 --keep-going -D suppress_warnings=ref.doc"

