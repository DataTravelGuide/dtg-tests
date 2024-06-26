#!/bin/bash
set -x

date_str=`date "+%Y_%m_%d_%H_%M_%S"`

. ./local_conf
. ./utils/utils.sh

if [ -z "$CBD_DIR" ]; then
	echo "CBD_DIR must be set in local_conf: CBD_DIR=/xxx/xxxx"
	exit 1
fi

if [ ! -z "$CBD_TESTS_SETUP_CMD" ]; then
	$CBD_TESTS_SETUP_CMD
fi

# enable request stats
replace_option $CBD_DIR/include/cbd.h "\#undef CBD_REQUEST_STATS" "\#define CBD_REQUEST_STATS"

# build and insmod cbd
setup $1

prepare_cbd_devs
