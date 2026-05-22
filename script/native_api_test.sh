#!/bin/bash
#登录用户名
ACCOUNT=root
test_type=native_api_test
#初始环境存放路径
INIT_PATH=/data/atmos/zk_test
BUILD_PATH=${INIT_PATH}/save
ATMOS_PATH=${INIT_PATH}/atmos-e
TIMECHODB_PATH=${BUILD_PATH}/timecho
PYTHON_TOOL_PATH=${INIT_PATH}/python-native-api-testcase-enterprise
BK_PATH=${INIT_PATH}/native_api_test_report
#测试数据运行路径
TEST_INIT_PATH=/data/qa
TEST_TIMECHODB_PATH=${TEST_INIT_PATH}/timecho
TEST_PYTHON_TOOL_PATH=${TEST_INIT_PATH}/python-native-api-testcase-enterprise
############mysql信息##########################
MYSQLHOSTNAME="111.200.37.158" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD=${ATMOS_DB_PASSWORD}
DBNAME="QA_ATM"                   #数据库名称
TABLENAME="native_api_test_enterprise" #数据库中用例表的名称
############公用函数##########################
if [ "${PASSWORD}" = "" ]; then
	echo "需要关注密码设置！"
fi
############定义监控采集项初始值##########################
init_items() {
tests_num=0
errors_num=0
failures_num=0
skipped_num=0
successRate=0
cost_time=0
start_time=0
end_time=0
flag=0
}
set_timechodb() { # 准备 TimechoDB
	if [ ! -d "${TEST_TIMECHODB_PATH}" ]; then
		mkdir -p ${TEST_TIMECHODB_PATH}
	else
		rm -rf ${TEST_TIMECHODB_PATH}
		mkdir -p ${TEST_TIMECHODB_PATH}
	fi
	unzip ${TIMECHODB_PATH}/timechodb-*-SNAPSHOT-bin.zip -d ${TEST_TIMECHODB_PATH}/
}
check_timechodb_pid() { # 检查timechodb的pid，有就停止
	timechodb_pid=$(jps | grep DataNode | awk '{print $1}')
	if [ "${timechodb_pid}" = "" ]; then
		echo "未检测到DataNode程序！"
	else
		kill -9 ${timechodb_pid}
		echo "DataNode程序已停止！"
	fi
	timechodb_pid=$(jps | grep ConfigNode | awk '{print $1}')
	if [ "${timechodb_pid}" = "" ]; then
		echo "未检测到ConfigNode程序！"
	else
		kill -9 ${timechodb_pid}
		echo "ConfigNode程序已停止！"
	fi
	echo "程序检测和清理操作已完成！"
}
start_timechodb() { # 启动iotdb
	cd ${TEST_TIMECHODB_PATH}/timechodb-*-SNAPSHOT-bin
  cp -rf ${ATMOS_PATH}/conf/${test_type}/license activation/
  cp -rf ${ATMOS_PATH}/conf/${test_type}/.env .
	conf_start=$(./sbin/start-confignode.sh >/dev/null 2>&1 &)
	sleep 10
	data_start=$(./sbin/start-datanode.sh -H ${TEST_TIMECHODB_PATH}/dn_dump.hprof >/dev/null 2>&1 &)
	cd ~/
}
test_python_native_api_test() { # 测试Python原生接口
	# 拷贝Python工具到测试路径
	if [ ! -d "${TEST_PYTHON_TOOL_PATH}" ]; then
		mkdir -p ${TEST_PYTHON_TOOL_PATH}
	else
		rm -rf ${TEST_PYTHON_TOOL_PATH}
		mkdir -p ${TEST_PYTHON_TOOL_PATH}
	fi
	cp -rf ${PYTHON_TOOL_PATH}/* ${TEST_PYTHON_TOOL_PATH}/
	# 创建测试环境，安装测试依赖
	cd ${TEST_PYTHON_TOOL_PATH}
	python3 -m venv venv
	source venv/bin/activate
	pip3 install pytest
	pip3 install pyyaml
	pip3 install pytest-html
	pip3 install numpy==1.25.2
	pip3 install pandas==2.0.3
	pip3 install greenlet==2.0.2
	pip3 install ${BUILD_PATH}/python/apache_iotdb-*.dev0-py3-none-any.whl # 引入依赖
	if [ $? -ne 0 ]; then
		echo "引入iotdb依赖失败"
		tests_num=-3
		errors_num=-3
		failures_num=-3
		skipped_num=-3
		successRate=-3
		#结果写入mysql
		insert_sql_python="insert into ${TABLENAME} (test_date_time,commit_id,tests_num,errors_num,failures_num,skipped_num,successRate,start_time,end_time,cost_time,remark) values(${test_date_time},'${commit_id_iotdb}',${tests_num},${errors_num},${failures_num},${skipped_num},${successRate},'0','0',0,'PYTHON')"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql_python}"
		deactivate
		return 1
	fi
	# 开始测试
	echo "Python开始测试"
	cd ${TEST_PYTHON_TOOL_PATH}/tests
	start_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
	start_test=$(timeout 7200s bash -c "pytest --html=../reports/report.html")
	for (( t_wait = 0; t_wait <= 20; ))
	do
		cd ${TEST_PYTHON_TOOL_PATH}
		result_file=${TEST_PYTHON_TOOL_PATH}/reports/report.html
		if [ ! -f "$result_file" ]; then
			now_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
			t_time=$(($(date +%s -d "${now_time}") - $(date +%s -d "${start_time}")))
			if [ $t_time -ge 14400 ]; then
				echo "Python原生接口测试失败"
				flag=1
				break
			fi
			continue
		else
			echo "Python原生接口测试完成"
			break
		fi
	done
	end_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
	# 防止测试报告文档内容还未生成完全，导致脚本获取空值
	sleep 60
	deactivate
	if [ $flag -eq 0 ]; then
		#收集测试结果
		cd ${TEST_PYTHON_TOOL_PATH}
		# 从HTML报告中提取测试结果
		tests_num=$(grep -o '[0-9]\+ tests' ${TEST_PYTHON_TOOL_PATH}/reports/report.html | head -1 | grep -o '[0-9]\+')
		errors_num=$(grep -o '[0-9]\+ Error' ${TEST_PYTHON_TOOL_PATH}/reports/report.html | head -1 | grep -o '[0-9]\+')
		if [ -z "$errors_num" ]; then
			errors_num=0
		fi
		failures_num=$(grep -o '[0-9]\+ Failed' ${TEST_PYTHON_TOOL_PATH}/reports/report.html | head -1 | grep -o '[0-9]\+')
		if [ -z "$failures_num" ]; then
			failures_num=0
		fi
		skipped_num=$(grep -o '[0-9]\+ Skipped' ${TEST_PYTHON_TOOL_PATH}/reports/report.html | head -1 | grep -o '[0-9]\+')
		if [ -z "$skipped_num" ]; then
			skipped_num=0
		fi
		passed_num=$(grep -o '[0-9]\+ Passed' ${TEST_PYTHON_TOOL_PATH}/reports/report.html | head -1 | grep -o '[0-9]\+')
		if [ -z "$passed_num" ]; then
			passed_num=0
		fi
		if [ -z "$tests_num" ] || [ "$tests_num" -eq 0 ]; then
      successRate=0
    else
      successRate=$(echo "scale=2; ($passed_num / $tests_num) * 100" | bc)
    fi
		#结果写入mysql
		cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
		insert_sql_python="insert into ${TABLENAME} (test_date_time,commit_id,tests_num,errors_num,failures_num,skipped_num,successRate,start_time,end_time,cost_time,remark) values(${test_date_time},'${commit_id_iotdb}',${tests_num},${errors_num},${failures_num},${skipped_num},${successRate},'${start_time}','${end_time}',${cost_time},'PYTHON')"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql_python}"
		if [ $? -ne 0 ]; then
			echo "执行mysql命令失败"
			#收集测试结果
			tests_num=-5
			errors_num=-5
			failures_num=-5
			skipped_num=-5
			successRate=-5
			#结果写入mysql
			cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
			sql=$(cat <<EOF
			insert into ${TABLENAME} (test_date_time,commit_id,tests_num,errors_num,failures_num,skipped_num,successRate,start_time,end_time,cost_time,remark,insert_sql) values(${test_date_time},'${commit_id_iotdb}',${tests_num},${errors_num},${failures_num},${skipped_num},${successRate},'${start_time}','${end_time}',${cost_time},'PYTHON',"${insert_sql_python}")
EOF
			)
			mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "$sql"
			echo "备份Python原生接口测试报告"
      		mkdir -p /data/qa/backup/python/${last_cid_iotdb}_${failures_num}
      		cp -rf  ${TEST_PYTHON_TOOL_PATH}/reports/* /data/qa/backup/python/${last_cid_iotdb}_${failures_num}
			return 1
		fi
	else
		#收集测试结果
		cd ${TEST_PYTHON_TOOL_PATH}
		tests_num=-4
		errors_num=-4
		failures_num=-4
		skipped_num=-4
		successRate=-4
		#结果写入mysql
		cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
		insert_sql_python="insert into ${TABLENAME} (test_date_time,commit_id,tests_num,errors_num,failures_num,skipped_num,successRate,start_time,end_time,cost_time,remark) values(${test_date_time},'${commit_id_iotdb}',${tests_num},${errors_num},${failures_num},${skipped_num},${successRate},'${start_time}','${end_time}',${cost_time},'PYTHON')"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql_python}"
	fi
	#备份本次测试
}
mkdir -p "${INIT_PATH}"
echo "ontesting" > "${INIT_PATH}/test_type_file"
if [ ! -d "${BUILD_PATH}" ]; then
	mkdir -p ${BUILD_PATH}
fi
if [ ! -f "${INIT_PATH}/test_identifier_file" ]; then
	touch "${INIT_PATH}/test_identifier_file"
	cat > "${INIT_PATH}/test_identifier_file" <<EOF
is_update=false
commitTime=
commitId=
EOF
fi
# 初始化参数
init_items
# 获取当前测试对应的提交时间和commitID
test_date_time=$(sed -n 's/^commitTime=//p' "${INIT_PATH}/test_identifier_file" | head -n1 | tr -d '\r\n')
commit_id_iotdb=$(sed -n 's/^commitId=//p' "${INIT_PATH}/test_identifier_file" | head -n1 | tr -d '\r\n')
# 更新测试工具
cd ${PYTHON_TOOL_PATH}
git_pull=$(timeout 100s git pull)
# 对比判定是否启动测试
if [ "$(awk -F= '$1=="is_update"{print $2; exit}' "${INIT_PATH}/test_identifier_file" 2>/dev/null | tr -d '\r\n')" = "true" ]; then # 判断TimechoDB代码是否更新
	echo "TimechoDB 有新commit合入，需要执行测试"
	rm -rf ${BUILD_PATH}/*
	cp -r ${INIT_PATH}/build/* ${BUILD_PATH}
	check_timechodb_pid
	set_timechodb
	start_timechodb
	sleep 60
	# 测试Python原生接口
	echo "测试Python原生接口"
	test_python_native_api_test
	if [ $? -eq 1 ]; then
		sleep 60
		echo "Python测试失败"
	fi
	#停止TimechoDB程序
	check_timechodb_pid
	###############################测试完成###############################
	echo "本轮测试${test_date_time}已结束."
else # 没有更新则等待下一轮测试w1y
	echo "没有更新则等待下一轮更新"
	echo "native_api_test" > ${INIT_PATH}/test_type_file
	sleep 300
fi
