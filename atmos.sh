#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "atmos.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "atmos.sh requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi
#登录用户名
ACCOUNT=root
INIT_PATH=/root/zk_test
ATMOS_PATH=${INIT_PATH}/atmos-e
test_type_file=${INIT_PATH}/test_type_file


#启动后无限循环执行-之后加入crontab之后可以去掉该层循环
for (( comp_test = 1; comp_test <= 3;))
do
	read test_type <<<$(cat ${test_type_file} | awk -F+ '{print $1}')
	sleep 1

	cd ${ATMOS_PATH}
	git_pull=$(timeout 100s git fetch --all)
	git_pull=$(timeout 100s git reset --hard origin/main)
	git_pull=$(timeout 100s git pull)

	sleep 1
	if [ "$test_type" = "ontesting" ]; then
		echo “测试执行中。。。”
	elif [ "$test_type" = "compile" ]; then
		nohup bash ${ATMOS_PATH}/tools/compile.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	else
		scenario_script="${ATMOS_PATH}/script/scenarios/${test_type}.sh"
		if [ -f "${scenario_script}" ]; then
			nohup bash "${scenario_script}" >> "${INIT_PATH}/log_${test_type}" 2>&1 &
		else
			echo "unknown test_type: ${test_type}, missing scenario: ${scenario_script}"
		fi
	fi
	sleep 300s
done
