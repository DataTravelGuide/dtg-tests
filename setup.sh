#!/bin/bash
set -x

date_str=`date "+%Y_%m_%d_%H_%M_%S"`

source ./local_conf
source ./utils/utils.sh

# build and insmod cbd
setup $1
