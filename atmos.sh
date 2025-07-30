#!/bin/sh
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
	elif [ "$test_type" = "api_test" ]; then
		nohup sh ${ATMOS_PATH}/script/api_test.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	elif [ "$test_type" = "config_insert" ]; then
		nohup sh ${ATMOS_PATH}/script/config_insert.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	elif [ "$test_type" = "routine_test" ]; then
		nohup sh ${ATMOS_PATH}/script/routine_test.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	elif [ "$test_type" = "se_insert" ]; then
		nohup sh ${ATMOS_PATH}/script/se_insert.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	elif [ "$test_type" = "se_query" ]; then
		nohup sh ${ATMOS_PATH}/script/se_query.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	elif [ "$test_type" = "unse_insert" ]; then
		nohup sh ${ATMOS_PATH}/script/unse_insert.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	elif [ "$test_type" = "unse_query" ]; then
		nohup sh ${ATMOS_PATH}/script/unse_query.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	elif [ "$test_type" = "compile" ]; then
		nohup sh ${ATMOS_PATH}/tool/compile.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	else
		nohup sh ${ATMOS_PATH}/script/${test_type}.sh >> ${INIT_PATH}/log_${test_type} 2>&1 &
	fi
	sleep 300s
done
