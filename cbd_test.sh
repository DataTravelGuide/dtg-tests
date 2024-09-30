#!/bin/bash

set -ex

DIR=$(dirname $0)

git_send_email()
{
	local result=$1

	echo "From: Linggang Zeng <linggang.zeng@easystack.cn>" > /tmp/git_send_email.txt

	if [ ${result} == "SKIP" ]; then
		echo "Subject: [cbd-daily-test] $(date '+%Y.%m.%d-%H.%M.%S') SKIP" >> /tmp/git_send_email.txt
		echo "" >> /tmp/git_send_email.txt
		echo "No update, please refer to the previous test results." >> /tmp/git_send_email.txt
	elif [ ${result} != "PASS" ]; then
		echo "Subject: [cbd-daily-test] $(date '+%Y.%m.%d-%H.%M.%S') FAIL" >> /tmp/git_send_email.txt
		echo "" >> /tmp/git_send_email.txt
		echo "Something is wrong, please check!" >> /tmp/git_send_email.txt
		echo "1. cbd-test service log:" >> /tmp/git_send_email.txt
		echo "$(journalctl -u cbd-test -b)" >> /tmp/git_send_email.txt
		echo "" >> /tmp/git_send_email.txt
		echo "2. dmesg:" >> /tmp/git_send_email.txt
		echo "$(dmesg -T)" >> /tmp/git_send_email.txt
	else
		xfstests_dirs=$(ls /root/avocado/job-results/latest/test-results/ | grep xfstests)
		xfstest_results="PASS"
		for xfstests_dir in ${xfstests_dirs}; do
			if grep "Failures:" /root/avocado/job-results/latest/test-results/${xfstests_dir}/debug.log; then
				xfstest_results="FAIL"
				break
			fi
		done
		if [ ${xfstest_results} != "PASS" ]; then
			echo "Subject: [cbd-daily-test] $(date '+%Y.%m.%d-%H.%M.%S') FAIL" >> /tmp/git_send_email.txt
		else
			echo "Subject: [cbd-daily-test] $(date '+%Y.%m.%d-%H.%M.%S') PASS" >> /tmp/git_send_email.txt
		fi
		echo "" >> /tmp/git_send_email.txt

		i=0
		while true
		do
			id=$(jq -r .tests[${i}].id /root/avocado/job-results/latest/results.json)
			if [ "${id}" = "null" ]; then
				break
			fi
			status=$(jq -r .tests[${i}].status /root/avocado/job-results/latest/results.json)
			if [ "${status}" = "null" ]; then
				break
			fi
			echo "ID: ${id}, Status: ${status}" >> /tmp/git_send_email.txt
			(( i = i + 1 ))
		done
	fi

	# Try 3 times every 10 seconds if git send-email fail.
	for i in $(seq 3)
	do
		if git send-email  \
			--no-signed-off-by-cc \
			--no-suppress-from \
			--suppress-cc=all \
			--to dongsheng.yang@linux.dev,cengku@gmail.com,linggang.zeng@easystack.cn \
			/tmp/git_send_email.txt; then
			rm -rf /tmp/git_send_email.txt
			break
		fi
		sleep 10
	done
}

git_push_results()
{
	local result=$1
	local current_resutls_dir=$(date '+%Y.%m.%d-%H.%M.%S')

	. ${DIR}/local_conf
	cd ${CBD_TESTS_RESULTS_DIR}

	mkdir -p ${current_resutls_dir}

	journalctl -u cbd-test -b > ./${current_resutls_dir}/cbd-test.log
	dmesg -T > ./${current_resutls_dir}/dmesg.log

	if [ ${result} != "PASS" ]; then
		git add ${current_resutls_dir}
		git commit -s -m "${current_resutls_dir} cbd test FAIL"
	else
		xfstests_dirs=$(ls /root/avocado/job-results/latest/test-results/ | grep xfstests)
		for xfstests_dir in ${xfstests_dirs}; do
			mkdir -p ./${current_resutls_dir}/${xfstests_dir}
			cp /root/avocado/job-results/latest/test-results/${xfstests_dir}/debug.log ./${current_resutls_dir}/${xfstests_dir}/
		done
		cp /root/avocado/job-results/latest/test-results/output.cvs ./${current_resutls_dir}

		git add ${current_resutls_dir}

		xfstest_results="PASS"
		for xfstests_dir in ${xfstests_dirs}; do
			if grep "Failures:" /root/avocado/job-results/latest/test-results/${xfstests_dir}/debug.log; then
				xfstest_results="FAIL"
				break
			fi
		done
		if [ ${xfstest_results} != "PASS" ]; then
			git commit -s -m "${current_resutls_dir} cbd test FAIL"
		else
			git commit -s -m "${current_resutls_dir} cbd test PASS"
		fi
	fi

	git push

	cd -
}

prepare()
{
	. ${DIR}/local_conf

	cd ${CBD_TESTS_KERNEL_DIR}

	old_commit=$(git rev-parse HEAD)

	git pull

	new_commit=$(git rev-parse HEAD)

	if [ ${old_commit} == ${new_commit} ]; then
		echo "Now force to do test."
		# git_send_email "SKIP"
		# exit 0
	fi

	make -j 42 && make -j 42 modules_install && make install && grub-set-default 0 && touch /cbd_test && reboot
}

do_test()
{
	if [ -e "/cbd_test" ]; then
		cd ${DIR}
		if bash test_all.sh; then
			git_send_email "PASS"
			git_push_results "PASS"
		else
			git_send_email "FAIL"
			git_push_results "FAIL"
		fi
		cd -
		rm -rf /cbd_test
	fi
}

main()
{
	if [ $1 == "prepare" ]; then
		prepare
	else
		do_test
	fi
}

main $1
