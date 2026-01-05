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
make
