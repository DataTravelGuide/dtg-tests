#!/bin/bash
set -ex

date_str=`date "+%Y_%m_%d_%H_%M_%S"`

DRY_RUN=0

SUFFIX=""
if [ "$1" = "quick" ]; then
	SUFFIX="_quick"
	echo "quick cbd test."
else
	echo "full cbd test."
fi

if [ "$2" = "dryrun" ]; then
	DRY_RUN=1
	echo "dryrun....."
fi

source ./local_conf
CBD_TESTS_DIR=`pwd`

source ./utils/utils.sh

source /etc/os-release
case "$ID" in
debian|ubuntu|devuan|elementary|softiron)
	echo "ubuntu"
	apt install -y  fio python3 python3-pip
        ;;
rocky|centos|fedora|rhel|ol|virtuozzo)
	echo "centos"
	yum install -y  fio python3 python3-pip
        ;;
*)
        echo "$ID is unknown, dependencies will have to be installed manually."
        exit 1
        ;;
esac

# install requirements
pip install avocado-framework==96.0 avocado-framework-plugin-varianter-yaml-to-mux==96.0 avocado-framework-plugin-result-html==96.0

# build and insmod cbd
setup

# replace default options with the real options
cd ${CBD_TESTS_DIR}
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml XFSTESTS_DIR_DEFAULT ${CBD_TESTS_XFSTESTS_DIR}
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml CBD_TESTS_DIR_DEFAULT ${CBD_TESTS_DIR}
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml SCRATCH_MNT_DEFAULT ${XFSTESTS_SCRATCH_MNT}
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml TEST_MNT_DEFAULT ${XFSTESTS_TEST_MNT}
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml TEST_DEV_DEFAULT /dev/cbd0
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml SCRATCH_DEV_DEFAULT /dev/cbd1
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml CACHE_TEST_DEFAULT /dev/cbd2
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml CACHE_SCRATCH_DEFAULT /dev/cbd3


replace_option fio.py.data/fio${SUFFIX}.yaml CBD_DEV_PATH /dev/cbd0
replace_option fio.py.data/fio${SUFFIX}.yaml OUTPUT_FILE "output.cvs"

#replace_option upgradeonline.py.data/upgradeonline${SUFFIX}.yaml CBD_TESTS_DIR_DEFAULT ${CBD_TESTS_DIR}
#replace_option upgradeonline.py.data/upgradeonline${SUFFIX}.yaml CBD_DEV_DEFAULT /dev/cbd0

if [ ${DRY_RUN} -eq 0 ]; then
	./all_test${SUFFIX}.py
fi

if [ ! -z "$CBD_TESTS_POST_TEST_CMDS" ]; then
	${CBD_TESTS_POST_TEST_CMDS}
fi

replace_option fio.py.data/fio${SUFFIX}.yaml "output.cvs" OUTPUT_FILE
replace_option fio.py.data/fio${SUFFIX}.yaml /dev/cbd0 CBD_DEV_PATH

replace_option xfstests.py.data/xfstests${SUFFIX}.yaml /dev/cbd3 CACHE_SCRATCH_DEFAULT
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml /dev/cbd2 CACHE_TEST_DEFAULT
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml /dev/cbd1 SCRATCH_DEV_DEFAULT
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml /dev/cbd0 TEST_DEV_DEFAULT
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml ${XFSTESTS_TEST_MNT} TEST_MNT_DEFAULT
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml ${XFSTESTS_SCRATCH_MNT} SCRATCH_MNT_DEFAULT
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml ${CBD_TESTS_DIR} CBD_TESTS_DIR_DEFAULT
replace_option xfstests.py.data/xfstests${SUFFIX}.yaml ${CBD_TESTS_XFSTESTS_DIR} XFSTESTS_DIR_DEFAULT

# cleanup 
cleanup
