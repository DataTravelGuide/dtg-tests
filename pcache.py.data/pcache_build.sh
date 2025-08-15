#!/bin/bash
set -ex

: "${linux_path:=/workspace/linux_compile}"
PATCH_FILE="$(realpath "$(dirname "$0")/../0001-dm-pcache-add-build-flags-for-testing.patch")"

pushd "$linux_path"
cleanup() {
    patch -Rp1 < "$PATCH_FILE" || true
    popd
}
trap cleanup EXIT

patch -Np1 < "$PATCH_FILE"

make M=drivers/md/dm-pcache
make htmldocs SPHINXDIRS=admin-guide/device-mapper SPHINXOPTS="-W -n -j1 --keep-going -D suppress_warnings=ref.doc"

