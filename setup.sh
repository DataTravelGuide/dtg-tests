#!/bin/bash
set -x

date_str=`date "+%Y_%m_%d_%H_%M_%S"`

. ./local_conf
. ./utils/utils.sh

# build and insmod cbd
setup $1
