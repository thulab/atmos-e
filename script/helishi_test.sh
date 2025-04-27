#!/bin/bash
#登录用户名
ACCOUNT=Administrator
test_type=helishi_test
#初始环境存放路径
INIT_PATH=/root/zk_test_helishi
ATMOS_PATH=${INIT_PATH}/atmos-e
BM_PATH=${INIT_PATH}/iot-benchmark
BUCKUP_PATH=/nasdata/repository/helishi_test
REPOS_PATH=/nasdata/repository/master
TEST_PATH=${INIT_PATH}/first-rest-test
TEST_IOTDB_PATH=${TEST_PATH}/apache-iotdb
TEST_IOTDB_PATH_W="D:\\first-rest-test"
TEST_File_PATH_W="C:\\run_test.vbs"
# 1. org.apache.iotdb.consensus.simple.SimpleConsensus
# 2. org.apache.iotdb.consensus.ratis.RatisConsensus
# 3. org.apache.iotdb.consensus.iot.IoTConsensus
protocol_class=(0 org.apache.iotdb.consensus.simple.SimpleConsensus org.apache.iotdb.consensus.ratis.RatisConsensus org.apache.iotdb.consensus.iot.IoTConsensus)
IoTDB_IP=172.20.31.7
Control=172.20.31.25
insert_list=(P10000 P50000)
############mysql信息##########################
MYSQLHOSTNAME="111.200.37.158" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD=${ATMOS_DB_PASSWORD}
DBNAME="QA_ATM"  #数据库名称
TABLENAME="test_result_helishi_test" #数据库中表的名称
TASK_TABLENAME="commit_history" #数据库中任务表的名称
############prometheus##########################
metric_server="172.20.70.11:9090"
############公用函数##########################
if [ "${PASSWORD}" = "" ]; then
echo "需要关注密码设置！"
fi
#echo "Started at: " date -d today +"%Y-%m-%d %H:%M:%S"
init_items() {
############定义监控采集项初始值##########################
test_date_time=0
ts_type=0
data_type=0
op_type=0
okPoint=0
okOperation=0
failPoint=0
failOperation=0
throughput=0
Latency=0
MIN=0
P10=0
P25=0
MEDIAN=0
P75=0
P90=0
P95=0
P99=0
P999=0
MAX=0
numOfSe0Level=0
start_time=0
end_time=0
cost_time=0
numOfUnse0Level=0
dataFileSize=0
maxNumofOpenFiles=0
maxNumofThread=0
errorLogSize=0
walFileSize=0
maxCPULoad=0
avgCPULoad=0
maxDiskIOOpsRead=0
maxDiskIOOpsWrite=0
maxDiskIOSizeRead=0
maxDiskIOSizeWrite=0
############定义监控采集项初始值##########################
}
set_env() { # 拷贝编译好的iotdb到测试路径
	if [ ! -d "${TEST_PATH}" ]; then
		mkdir -p ${TEST_PATH}
		mkdir -p ${TEST_PATH}/apache-iotdb
		mkdir -p ${TEST_PATH}/iotdbtest
	else
		rm -rf ${TEST_PATH}
		mkdir -p ${TEST_PATH}
		mkdir -p ${TEST_PATH}/apache-iotdb
		mkdir -p ${TEST_PATH}/iotdbtest
	fi
	cp -rf ${REPOS_PATH}/${commit_id}/apache-iotdb/* ${TEST_IOTDB_PATH}/
	#cp -rf /root/zk_test_helishi/apache-iotdb/* ${TEST_IOTDB_PATH}/
	cp -rf /root/zk_test_helishi/iotdbtest/iotdbtest.exe ${TEST_PATH}/iotdbtest/iotdbtest.exe
	mkdir -p ${TEST_IOTDB_PATH}/activation
	cp -rf ${ATMOS_PATH}/conf/${test_type}/license ${TEST_IOTDB_PATH}/activation/
	cp -rf ${ATMOS_PATH}/conf/${test_type}/.env ${TEST_IOTDB_PATH}/
}
modify_iotdb_config() { # iotdb调整内存，关闭合并
	#修改IoTDB的配置
	sed -i "s/^@REM set ON_HEAP_MEMORY=2G.*$/set ON_HEAP_MEMORY=2G/g" ${TEST_IOTDB_PATH}/conf/windows/datanode-env.bat
	sed -i "s/^@REM set ON_HEAP_MEMORY=2G.*$/set ON_HEAP_MEMORY=500M/g" ${TEST_IOTDB_PATH}/conf/windows/confignode-env.bat
	#清空配置文件
	# echo "只保留要修改的参数" > ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "data_region_group_extension_policy=CUSTOM" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "default_data_region_group_num_per_database=1" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "datanode_memory_proportion=11:6:1:0:0:2" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "compaction_write_throughput_mb_per_sec=4" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "compaction_read_throughput_mb_per_sec=10" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "enable_last_cache=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#关闭影响写入性能的其他功能
	echo "enable_seq_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "enable_unseq_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "enable_cross_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#修改集群名称
	echo "cluster_name=${test_type}" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#添加启动监控功能
	echo "cn_enable_metric=true" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "cn_enable_performance_stat=true" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "cn_metric_reporter_list=PROMETHEUS" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "cn_metric_level=ALL" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "cn_metric_prometheus_reporter_port=9081" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#添加启动监控功能
	echo "dn_enable_metric=true" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "dn_enable_performance_stat=true" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "dn_metric_reporter_list=PROMETHEUS" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "dn_metric_level=ALL" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "dn_metric_prometheus_reporter_port=9091" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	
	#echo "cn_internal_address=${IoTDB_IP}" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#echo "cn_seed_config_node=${IoTDB_IP}:10710" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#echo "dn_rpc_address=${IoTDB_IP}" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#echo "dn_internal_address=${IoTDB_IP}" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#echo "dn_seed_config_node=${IoTDB_IP}:10710" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
}
set_protocol_class() { 
	config_node=$1
	schema_region=$2
	data_region=$3
	#设置协议
	echo "config_node_consensus_protocol_class=${protocol_class[${config_node}]}" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "schema_region_consensus_protocol_class=${protocol_class[${schema_region}]}" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "data_region_consensus_protocol_class=${protocol_class[${data_region}]}" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
}
setup_env() {
	TEST_IP=$1
	echo "开始重置环境！"
	#ssh ${ACCOUNT}@${TEST_IP} "shutdown /f /r /t 0"
	pid3=$(ssh ${ACCOUNT}@${TEST_IP} "schtasks /Run /TN  run_clean")
	sleep 120
	rflag=0
	while true; do
		echo "当前连接：${ACCOUNT}@${TEST_IP}"
		ssh ${ACCOUNT}@${TEST_IP} "dir D:" >/dev/null 2>&1
		if [ $? -eq 0 ];then
			echo "${TEST_IP}已启动"
			break
		else
			echo "${TEST_IP}未启动"
			if [ $rflag -ge 5 ]; then
				break
			else
				#ssh ${ACCOUNT}@${TEST_IP} "shutdown /f /r /t 0"
				rflag=$[${rflag}+1]
			fi
			sleep 180
		fi
	done
	echo "setting env to ${TEST_IP} ..."
	#删除原有路径下所有
	ssh ${ACCOUNT}@${TEST_IP} "rmdir /s /q ${TEST_IOTDB_PATH_W}"
	ssh ${ACCOUNT}@${TEST_IP} "md ${TEST_IOTDB_PATH_W}"
	#复制三项到客户机
	scp -r ${TEST_PATH}/* ${ACCOUNT}@${TEST_IP}:${TEST_IOTDB_PATH_W}
	#启动IoTDB
	echo "starting IoTDB on ${TEST_IP} ..."
	pid3=$(ssh ${ACCOUNT}@${TEST_IP} "schtasks /Run /TN  run_iotdb")
	sleep 10
	for (( t_wait = 0; t_wait <= 50; t_wait++ ))
	do
	  str1=$(${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${TEST_IP} -p 6667 -u root -pw root -e "show cluster" | grep 'Total line number = 2')
	  if [ "$str1" = "Total line number = 2" ]; then
		echo "All Nodes is ready"
		flag=1
		break
	  else
		echo "All Nodes is not ready.Please wait ..."
		sleep 3
		continue
	  fi
	done
	if [ "$flag" = "0" ]; then
	  echo "All Nodes is not ready!"
	  exit -1
	fi
}
start_benchmark() { # 启动benchmark
	cd ${BM_PATH}
	if [ -d "${BM_PATH}/logs" ]; then
		rm -rf ${BM_PATH}/logs
	fi
	if [ ! -d "${BM_PATH}/data" ]; then
		#bm_start=$(${BM_PATH}/benchmark.sh >/dev/null 2>&1 &)
		pid3=$(ssh ${ACCOUNT}@${TEST_IP} "schtasks /Run /TN  run_test")
	else
		rm -rf ${BM_PATH}/data
		#bm_start=$(${BM_PATH}/benchmark.sh >/dev/null 2>&1 &)
		pid3=$(ssh ${ACCOUNT}@${TEST_IP} "schtasks /Run /TN  run_test")
	fi
	cd ~/
}
monitor_test_status() { # 监控测试运行状态，获取最大打开文件数量和最大线程数
	while true; do
		#确认是否测试已结束
		csvOutput=${BM_PATH}/data/csvOutput
		if [ ! -d "$csvOutput" ]; then
			now_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
			t_time=$(($(date +%s -d "${now_time}") - $(date +%s -d "${start_time}")))
			if [ $t_time -ge 7200 ]; then
				echo "测试2小时终止结束"
				end_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
				mkdir -p ${BM_PATH}/data/csvOutput
				cd ${BM_PATH}/data/csvOutput
				touch Stuck_result.csv
				cd ~
				break
			fi
			continue
		else
			end_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
			echo "${ts_type}写入已完成！"
			break
		fi
	done
}
function get_single_index() {
    # 获取 prometheus 单个指标的值
    local end=$2
    local url="http://${metric_server}/api/v1/query"
    local data_param="--data-urlencode query=$1 --data-urlencode 'time=${end}'"
    index_value=$(curl -G -s $url ${data_param} | jq '.data.result[0].value[1]'| tr -d '"')
	if [[ "$index_value" == "null" || -z "$index_value" ]]; then 
		index_value=0
	fi
	echo ${index_value}
}
collect_monitor_data() { # 收集iotdb数据大小，顺、乱序文件数量
	dataFileSize=0
	walFileSize=0
	numOfSe0Level=0
	numOfUnse0Level=0
	maxNumofOpenFiles=0
	maxNumofThread_C=0
	maxNumofThread_D=0
	maxNumofThread=0
	throughput=0
	#调用监控获取数值
	dataFileSize=$(get_single_index "sum(file_global_size{instance=~\"${IoTDB_IP}:9091\"})" $m_end_time)
	dataFileSize=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize'/'1048576'}'`
	dataFileSize=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize'/'1024'}'`
	numOfSe0Level=$(get_single_index "sum(file_global_count{instance=~\"${IoTDB_IP}:9091\",name=\"seq\"})" $m_end_time)
	numOfUnse0Level=$(get_single_index "sum(file_global_count{instance=~\"${IoTDB_IP}:9091\",name=\"unseq\"})" $m_end_time)
	maxNumofThread_C=$(get_single_index "max_over_time(process_threads_count{instance=~\"${IoTDB_IP}:9081\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxNumofThread_D=$(get_single_index "max_over_time(process_threads_count{instance=~\"${IoTDB_IP}:9091\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	let maxNumofThread=${maxNumofThread_C}+${maxNumofThread_D}
	maxNumofOpenFiles=$(get_single_index "max_over_time(file_count{instance=~\"${IoTDB_IP}:9091\",name=\"open_file_handlers\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	walFileSize=$(get_single_index "max_over_time(file_size{instance=~\"${IoTDB_IP}:9091\",name=~\"wal\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	walFileSize=`awk 'BEGIN{printf "%.2f\n",'$walFileSize'/'1048576'}'`
	walFileSize=`awk 'BEGIN{printf "%.2f\n",'$walFileSize'/'1024'}'`
	throughput=$(get_single_index "sum(rate(quantity_total{instance=~\"${IoTDB_IP}:9091\",database!=\"root.__system\"}[1m])) by (database)" $m_end_time)
	maxCPULoad=$(get_single_index "max_over_time(sys_cpu_load{instance=~\"${IoTDB_IP}:9091\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	avgCPULoad=$(get_single_index "avg_over_time(sys_cpu_load{instance=~\"${IoTDB_IP}:9091\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	#DiskIO无法获取 - windows环境限制
	maxDiskIOOpsRead=$(get_single_index "rate(disk_io_ops{instance=~\"${IoTDB_IP}:9091\",disk_id=~\"vdc\",type=~\"read\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOOpsWrite=$(get_single_index "rate(disk_io_ops{instance=~\"${IoTDB_IP}:9091\",disk_id=~\"vdc\",type=~\"write\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOSizeRead=$(get_single_index "rate(disk_io_size{instance=~\"${IoTDB_IP}:9091\",disk_id=~\"vdc\",type=~\"read\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOSizeWrite=$(get_single_index "rate(disk_io_size{instance=~\"${IoTDB_IP}:9091\",disk_id=~\"vdc\",type=~\"write\"}[$((m_end_time-m_start_time))s])" $m_end_time)
}
mv_config_file() { # 移动配置文件
	ssh ${ACCOUNT}@${TEST_IP} "del ${TEST_File_PATH_W}"
	scp ${ATMOS_PATH}/conf/${test_type}/$1 ${ACCOUNT}@${TEST_IP}:${TEST_File_PATH_W}
}
test_operation() {
	TEST_IP=$1
	protocol_class=$2
	echo "开始测试！"
	for (( i = 0; i < ${#insert_list[*]}; i++ ))
	do
		#复制当前程序到执行位置
		data_type=${insert_list[${i}]}
		set_env
		modify_iotdb_config
		if [ "${protocol_class}" = "111" ]; then
			set_protocol_class 1 1 1
		elif [ "${protocol_class}" = "222" ]; then
			set_protocol_class 2 2 2
		elif [ "${protocol_class}" = "223" ]; then
			set_protocol_class 2 2 3
		elif [ "${protocol_class}" = "211" ]; then
			set_protocol_class 2 1 1
		else
			echo "协议设置错误！"
			return
		fi
		#设置环境并启动IoTDB
		setup_env ${TEST_IP}	
		echo "写入测试开始！"
		start_time=`date -d today +"%Y-%m-%d %H:%M:%S"`
		m_start_time=$(date +%s)
		mv_config_file ${data_type}
		start_benchmark 
		#等待1分钟
		sleep 60
		monitor_test_status ${TEST_IP}
		m_end_time=$(date +%s)
		collect_monitor_data
		cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
		insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,ts_type,data_type,op_type,okPoint,okOperation,failPoint,failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,errorLogSize,walFileSize,maxCPULoad,avgCPULoad,remark) values(${commit_date_time},${test_date_time},'${commit_id}','${author}','${ts_type}','${data_type}','INGESTION',${okPoint},${okOperation},${failPoint},${failOperation},${throughput},${Latency},${MIN},${P10},${P25},${MEDIAN},${P75},${P90},${P95},${P99},${P999},${MAX},${numOfSe0Level},'${start_time}','${end_time}',${cost_time},${numOfUnse0Level},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${errorLogSize},${walFileSize},${maxCPULoad},${avgCPULoad},'${protocol_class}')"
		echo ${insert_sql}
		echo ${commit_id}版本${ts_type}写入${data_type}数据的${okPoint}点平均耗时${Latency}毫秒。吞吐率为：${throughput} 点/秒
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
		pid3=$(ssh ${ACCOUNT}@${TEST_IP} "schtasks /Run /TN  run_clean")
		#查询测试 TODO
	done
}
echo "ontesting" > ${INIT_PATH}/test_type_file
query_sql="SELECT commit_id,',',author,',',commit_date_time,',' FROM ${TASK_TABLENAME} WHERE ${test_type} = 'retest' ORDER BY commit_date_time desc limit 1 "
result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${query_sql}")
commit_id=$(echo $result_string| awk -F, '{print $4}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
author=$(echo $result_string| awk -F, '{print $5}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
commit_date_time=$(echo $result_string | awk -F, '{print $6}' | sed s/-//g | sed s/://g | sed s/[[:space:]]//g | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
##查询是否有复测任务
if [ "${commit_id}" = "" ]; then
	query_sql="SELECT commit_id,',',author,',',commit_date_time,',' FROM ${TASK_TABLENAME} WHERE ${test_type} is NULL ORDER BY commit_date_time desc limit 1 "
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${query_sql}")
	commit_id=$(echo $result_string| awk -F, '{print $4}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
	author=$(echo $result_string| awk -F, '{print $5}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
	commit_date_time=$(echo $result_string | awk -F, '{print $6}' | sed s/-//g | sed s/://g | sed s/[[:space:]]//g | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
fi
if [ "${commit_id}" = "" ]; then
	sleep 60s
else
	update_sql="update ${TASK_TABLENAME} set ${test_type} = 'ontesting' where commit_id = '${commit_id}'"
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}")
	echo "当前版本${commit_id}未执行过测试，即将编译后启动"
	init_items
	test_date_time=`date +%Y%m%d%H%M%S`
	test_operation ${IoTDB_IP} 223 
	###############################测试完成###############################
	echo "本轮测试${test_date_time}已结束."
	update_sql="update ${TASK_TABLENAME} set ${test_type} = 'done' where commit_id = '${commit_id}'"
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}")
	update_sql02="update ${TASK_TABLENAME} set ${test_type} = 'skip' where ${test_type} is NULL and commit_date_time < '${commit_date_time}'"
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql02}")
fi
echo "${test_type}" > ${INIT_PATH}/test_type_file