#!/bin/bash
set -x
env
cd ${kernel_dir}

# List of variable names to check
for var in ${config_list} ; do
    # Check if the variable is set and whether it's true or false
    if [ "${!var}" == "true" ]; then
        ./scripts/config --enable "$var"
    elif [ "${!var}" == "false" ]; then
        ./scripts/config --disable "$var"
    else
        echo "Warning: $var is ${!var} not set to 'true' or 'false'"
    fi
done

cat .config|grep CBD_

make prepare; make -j 42 M=drivers/block/cbd/

if [[ $? != 0 ]]; then
	exit 1
fi
