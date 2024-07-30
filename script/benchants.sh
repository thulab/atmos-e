#!/bin/sh
#登录用户名
ACCOUNT=root
test_type=benchants
#初始环境存放路径
INIT_PATH=/root/zk_test
ATMOS_PATH=${INIT_PATH}/atmos-e
BM_PATH=${INIT_PATH}/tsbs
BUCKUP_PATH=/nasdata/repository/benchants
REPOS_PATH=/nasdata/repository/master
DATA_PATH=/root/dataset
# nohup bin/tsbs_generate_data --use-case="devops" --seed=123 --scale=1000 --timestamp-start="2022-07-25T00:00:00Z" --timestamp-end="2022-07-28T00:00:00Z" --log-interval="10s" --format="iotdb" | gzip > iotdb-1000hosts-3days-10s.gz &
# bin/tsbs_generate_queries --use-case="devops" --seed=123 --scale=1000 --timestamp-start="2022-07-25T00:00:00Z" --timestamp-end="2022-07-28T00:00:00Z" --queries=100000 --query-type="single-groupby-1-1-1" --format="iotdb"  > iotdb-query-single-groupby-1-1-1.txt
#测试数据运行路径
TEST_PATH=/data/cluster/first-rest-test
TEST_IOTDB_PATH=${TEST_PATH}/apache-iotdb
# 1. org.apache.iotdb.consensus.simple.SimpleConsensus
# 2. org.apache.iotdb.consensus.ratis.RatisConsensus
# 3. org.apache.iotdb.consensus.iot.IoTConsensus
protocol_class=(0 org.apache.iotdb.consensus.simple.SimpleConsensus org.apache.iotdb.consensus.ratis.RatisConsensus org.apache.iotdb.consensus.iot.IoTConsensus)

Small_IP=172.20.70.12
Medium_IP=172.20.70.10
Control=172.20.70.6
#query_list=(single-groupby-1-8-1 single-groupby-5-1-1 single-groupby-5-1-12 single-groupby-5-8-1 cpu-max-all-1 cpu-max-all-8 double-groupby-1 double-groupby-5 double-groupby-all high-cpu-all high-cpu-1 lastpoint groupby-orderby-limit)
query_list=(single-groupby-1-1-1 single-groupby-5-1-1)
############mysql信息##########################
MYSQLHOSTNAME="111.200.37.158" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD="iotdb2019"
DBNAME="QA_ATM"  #数据库名称
TABLENAME="test_result_benchants" #数据库中表的名称
TASK_TABLENAME="commit_history" #数据库中任务表的名称
############prometheus##########################
metric_server="172.20.70.11:9090"
############公用函数##########################
#echo "Started at: " date -d today +"%Y-%m-%d %H:%M:%S"
init_items() {
############定义监控采集项初始值##########################
test_date_time=0
server_kind=0
throughput_metrics=0
throughput_rows=0
query_rate=0
MIN_NUM=0
MED_NUM=0
MEAN_NUM=0
MAX_NUM=0
STDDEV_NUM=0
SUM_NUM=0 
COUNT_NUM=0
numOfSe0Level=0
numOfUnse0Level=0
start_time=0
end_time=0
cost_time=0
dataFileSize=0
maxNumofOpenFiles=0
maxNumofThread=0
errorLogSize=0
walFileSize=0
round_num=0
maxCPULoad=0
avgCPULoad=0
maxDiskIOOpsRead=0
maxDiskIOOpsWrite=0
maxDiskIOSizeRead=0
maxDiskIOSizeWrite=0
############定义监控采集项初始值##########################
}
local_ip=`ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"`
sendEmail() {
sendEmail=$(${TOOLS_PATH}/sendEmail.sh $1 >/dev/null 2>&1 &)
}
check_benchmark_pid() { # 检查benchmark的pid，有就停止
	monitor_pid=$(ps aux | grep tsbs_ |grep -v grep| awk '{print $2}')
	if [ "${monitor_pid}" = "" ]; then
		echo "未检测到监控程序！"
	else
		kill -9 ${monitor_pid}
		echo "BM程序已停止！"
	fi
}
check_iotdb_pid() { # 检查iotdb的pid，有就停止
	iotdb_pid=$(jps | grep DataNode | awk '{print $1}')
	if [ "${iotdb_pid}" = "" ]; then
		echo "未检测到DataNode程序！"
	else
		kill -9 ${iotdb_pid}
		echo "DataNode程序已停止！"
	fi
	iotdb_pid=$(jps | grep ConfigNode | awk '{print $1}')
	if [ "${iotdb_pid}" = "" ]; then
		echo "未检测到ConfigNode程序！"
	else
		kill -9 ${iotdb_pid}
		echo "ConfigNode程序已停止！"
	fi
	iotdb_pid=$(jps | grep IoTDB | awk '{print $1}')
	if [ "${iotdb_pid}" = "" ]; then
		echo "未检测到IoTDB程序！"
	else
		kill -9 ${iotdb_pid}
		echo "IoTDB程序已停止！"
	fi
	echo "程序检测和清理操作已完成！"
}
set_env() { # 拷贝编译好的iotdb到测试路径
	if [ ! -d "${TEST_PATH}" ]; then
		mkdir -p ${TEST_PATH}
		mkdir -p ${TEST_PATH}/apache-iotdb
	else
		rm -rf ${TEST_PATH}
		mkdir -p ${TEST_PATH}
		mkdir -p ${TEST_PATH}/apache-iotdb
	fi
	
	cp -rf ${REPOS_PATH}/${commit_id}/apache-iotdb/* ${TEST_PATH}/apache-iotdb/
}
modify_iotdb_config() { # iotdb调整内存，关闭合并
	#修改IoTDB的配置
	#sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"20G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
	#清空配置文件
	# echo "只保留要修改的参数" > ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	echo "query_timeout_threshold=6000000" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#关闭影响写入性能的其他功能
	#echo "enable_seq_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#echo "enable_unseq_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	#echo "enable_cross_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
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
	ssh ${ACCOUNT}@${TEST_IP} "sudo reboot"
	sleep 60
	echo "setting env to ${TEST_IP} ..."
	#删除原有路径下所有
	ssh ${ACCOUNT}@${TEST_IP} "rm -rf ${TEST_PATH}"
	ssh ${ACCOUNT}@${TEST_IP} "mkdir -p ${TEST_PATH}"
	#复制三项到客户机
	mkdir -p ${TEST_PATH}/apache-iotdb/activation
	cp -rf ${ATMOS_PATH}/conf/${test_type}/${TEST_IP} ${TEST_PATH}/apache-iotdb/activation/license
	scp -r ${TEST_PATH}/* ${ACCOUNT}@${TEST_IP}:${TEST_PATH}/
	#启动ConfigNode节点
	echo "starting IoTDB ConfigNode on ${TEST_IP} ..."
	pid3=$(ssh ${ACCOUNT}@${TEST_IP} "${TEST_IOTDB_PATH}/sbin/start-confignode.sh  > /dev/null 2>&1 &")
	#主节点需要先启动，所以等待10秒是为了保证主节点启动完毕
	sleep 5
	#启动DataNode节点
	echo "starting IoTDB DataNode on ${TEST_IP} ..."
	pid3=$(ssh ${ACCOUNT}@${TEST_IP} "${TEST_IOTDB_PATH}/sbin/start-datanode.sh   > /dev/null 2>&1 &")
	#等待60s，让服务器完成前期准备
	sleep 10
	for (( t_wait = 0; t_wait <= 50; t_wait++ ))
	do
	  str1=$(ssh ${ACCOUNT}@${TEST_IP} "${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${TEST_IP} -p 6667 -u root -pw root -e \"show cluster\" | grep 'Total line number = 2'")
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
setup_env_q() {
	TEST_IP=$1
	echo "开始重置环境！"
	ssh ${ACCOUNT}@${TEST_IP} "sudo reboot"
	sleep 60
	echo "setting env to ${TEST_IP} ..."
	#删除原有路径下所有
	ssh ${ACCOUNT}@${TEST_IP} "rm -rf ${TEST_PATH}"
	ssh ${ACCOUNT}@${TEST_IP} "mkdir -p ${TEST_PATH}"
	#复制三项到客户机
	
	mkdir -p ${TEST_PATH}/apache-iotdb/activation
	cp -rf ${ATMOS_PATH}/conf/${test_type}/${TEST_IP} ${TEST_PATH}/apache-iotdb/activation/license
	
	scp -r ${TEST_PATH}/* ${ACCOUNT}@${TEST_IP}:${TEST_PATH}/
	ssh ${ACCOUNT}@${TEST_IP} "cp -rf ${DATA_PATH}/data ${TEST_IOTDB_PATH}/"
	#启动ConfigNode节点
	echo "starting IoTDB ConfigNode on ${TEST_IP} ..."
	pid3=$(ssh ${ACCOUNT}@${TEST_IP} "${TEST_IOTDB_PATH}/sbin/start-confignode.sh  > /dev/null 2>&1 &")
	#主节点需要先启动，所以等待10秒是为了保证主节点启动完毕
	sleep 5
	#启动DataNode节点
	echo "starting IoTDB DataNode on ${TEST_IP} ..."
	pid3=$(ssh ${ACCOUNT}@${TEST_IP} "${TEST_IOTDB_PATH}/sbin/start-datanode.sh   > /dev/null 2>&1 &")
	#等待60s，让服务器完成前期准备
	sleep 10
	for (( t_wait = 0; t_wait <= 50; t_wait++ ))
	do
	  str1=$(ssh ${ACCOUNT}@${TEST_IP} "${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${TEST_IP} -p 6667 -u root -pw root -e \"show cluster\" | grep 'Total line number = 2'")
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
monitor_test_status() { # 监控测试运行状态，获取最大打开文件数量和最大线程数
	TEST_IP=$1
	while true; do
		#确认是否测试已结束
		flag=0
		str1=$(ssh ${ACCOUNT}@${Control} "ps aux | grep tsbs_ |grep -v grep | wc -l" 2>/dev/null)
		if [ "$str1" = "1" ]; then
			echo "测试未结束:${Control}"  > /dev/null 2>&1 &
		else
			echo "测试已结束:${Control}"
			flag=$[${flag}+1]
		fi
		now_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
		t_time=$(($(date +%s -d "${now_time}") - $(date +%s -d "${start_time}")))
		if [ $t_time -ge 7200 ]; then
			echo "测试失败"  #倒序输入形成负数结果
			end_time=-1
			cost_time=-1
			break
		fi
		if [ "$flag" = "1" ]; then
			end_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
			cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
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
	TEST_IP=$1
	dataFileSize=0
	walFileSize=0
	numOfSe0Level=0
	numOfUnse0Level=0
	maxNumofOpenFiles=0
	maxNumofThread_C=0
	maxNumofThread_D=0
	maxNumofThread=0
	#调用监控获取数值
	dataFileSize=$(get_single_index "sum(file_global_size{instance=~\"${TEST_IP}:9091\"})" $m_end_time)
	dataFileSize=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize'/'1048576'}'`
	dataFileSize=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize'/'1024'}'`
	numOfSe0Level=$(get_single_index "sum(file_global_count{instance=~\"${TEST_IP}:9091\",name=\"seq\"})" $m_end_time)
	numOfUnse0Level=$(get_single_index "sum(file_global_count{instance=~\"${TEST_IP}:9091\",name=\"unseq\"})" $m_end_time)
	maxNumofThread_C=$(get_single_index "max_over_time(process_threads_count{instance=~\"${TEST_IP}:9081\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxNumofThread_D=$(get_single_index "max_over_time(process_threads_count{instance=~\"${TEST_IP}:9091\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	let maxNumofThread=${maxNumofThread_C}+${maxNumofThread_D}
	maxNumofOpenFiles=$(get_single_index "max_over_time(file_count{instance=~\"${TEST_IP}:9091\",name=\"open_file_handlers\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	walFileSize=$(get_single_index "max_over_time(file_size{instance=~\"${TEST_IP}:9091\",name=~\"wal\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	walFileSize=`awk 'BEGIN{printf "%.2f\n",'$walFileSize'/'1048576'}'`
	walFileSize=`awk 'BEGIN{printf "%.2f\n",'$walFileSize'/'1024'}'`
	maxCPULoad=$(get_single_index "max_over_time(sys_cpu_load{instance=~\"${TEST_IP}:9091\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	avgCPULoad=$(get_single_index "avg_over_time(sys_cpu_load{instance=~\"${TEST_IP}:9091\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOOpsRead=$(get_single_index "rate(disk_io_ops{instance=~\"${TEST_IP}:9091\",disk_id=~\"vdc\",type=~\"read\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOOpsWrite=$(get_single_index "rate(disk_io_ops{instance=~\"${TEST_IP}:9091\",disk_id=~\"vdc\",type=~\"write\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOSizeRead=$(get_single_index "rate(disk_io_size{instance=~\"${TEST_IP}:9091\",disk_id=~\"vdc\",type=~\"read\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOSizeWrite=$(get_single_index "rate(disk_io_size{instance=~\"${TEST_IP}:9091\",disk_id=~\"vdc\",type=~\"write\"}[$((m_end_time-m_start_time))s])" $m_end_time)
}
backup_test_data() { # 备份测试数据
	TEST_IP=$2
	sudo mkdir -p ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}/$3
	str1=$(ssh ${ACCOUNT}@${TEST_IP} "rm -rf ${TEST_IOTDB_PATH}/data" 2>/dev/null)
	scp -r ${ACCOUNT}@${TEST_IP}:${TEST_IOTDB_PATH}/ ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}/$3
	sudo cp -rf ${BM_PATH}/TestResult/ ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}/$3
}
mv_config_file() { # 移动配置文件
	rm -rf ${BM_PATH}/conf/config.properties
	cp -rf ${ATMOS_PATH}/conf/${test_type}/$1/$2 ${BM_PATH}/conf/config.properties
}
test_operation() {
	server_kind=$1
	TEST_IP=$2
	protocol_class=$3
	echo "开始测试${server_kind}机型！"
	#复制当前程序到执行位置
	set_env
	modify_iotdb_config
	if [ "${server_kind}" = "medium" ]; then
		#修改IoTDB的配置
		sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"10G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
		sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"2G\"/g" ${TEST_IOTDB_PATH}/conf/confignode-env.sh
    elif [ "${server_kind}" = "small" ]; then
        #修改IoTDB的配置
		sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"4G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
		sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"2G\"/g" ${TEST_IOTDB_PATH}/conf/confignode-env.sh
	else
		echo "服务器类型错误！"
		return
	fi
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
	echo "测试开始！"
	rm -rf ${BM_PATH}/TestResult/*
	echo "写入测试开始！"
	start_time=`date -d today +"%Y-%m-%d %H:%M:%S"`
	m_start_time=$(date +%s)
	nohup cat ${BM_PATH}/iotdb-1000hosts-3days-10s.gz | gunzip | ${BM_PATH}/bin/tsbs_load_iotdb --host="${TEST_IP}" --port="6667" --user="root" --password="root" --timeout=1000 --workers=100 --batch-size=1000 --tablet-size=0 > ${BM_PATH}/TestResult/write_output.log 2>&1 &
	#等待1分钟
	sleep 60
	monitor_test_status ${TEST_IP}
	#测试结果收集写入数据库
	#收集启动后基础监控数据
	m_end_time=$(date +%s)
	collect_monitor_data ${TEST_IP}
	test_result_status=0
	test_result_status=$(grep -n 'error' ${Outputfile} | wc -l)
	echo ${test_result_status}
	if [ "${test_result_status}" = "0" ]; then
		
		Outputfile=${BM_PATH}/TestResult/write_output.log
		read throughput_metrics <<<$(cat ${Outputfile} | grep "metrics/sec" | sed -n '1,1p' | awk '{print $11}')
		read throughput_rows <<<$(cat ${Outputfile} | grep "rows/sec" | sed -n '1,1p' | awk '{print $11}')
	else
		throughput_metrics=-3
		throughput_rows=-3
	fi
	insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,server_kind,throughput_metrics,throughput_rows,query_rate,MIN_NUM,MEAN_NUM,MED_NUM,MAX_NUM,STDDEV_NUM,SUM_NUM,COUNT_NUM,numOfSe0Level,numOfUnse0Level,start_time,end_time,cost_time,dataFileSize,maxNumofOpenFiles,maxNumofThread,errorLogSize,walFileSize,avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,remark) values(${commit_date_time},${test_date_time},'${commit_id}','${author}','${server_kind}',${throughput_metrics},${throughput_rows},${query_rate},${MIN_NUM},${MEAN_NUM},${MED_NUM},${MAX_NUM},${STDDEV_NUM},${SUM_NUM},${COUNT_NUM},${numOfSe0Level},${numOfUnse0Level},'${start_time}','${end_time}',${cost_time},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${errorLogSize},${walFileSize},${avgCPULoad},${maxCPULoad},${maxDiskIOSizeRead},${maxDiskIOSizeWrite},${maxDiskIOOpsRead},${maxDiskIOOpsWrite},'write')"
	echo "${insert_sql}"
	mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
	backup_test_data ${server_kind} ${TEST_IP} write
}
test_operation_q() {
	server_kind=$1
	TEST_IP=$2
	protocol_class=$3
	echo "开始测试${server_kind}机型！"
	#复制当前程序到执行位置
	set_env
	modify_iotdb_config
	if [ "${server_kind}" = "medium" ]; then
		#修改IoTDB的配置
		sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"10G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
		sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"2G\"/g" ${TEST_IOTDB_PATH}/conf/confignode-env.sh
		#关闭影响写入性能的其他功能
		echo "enable_seq_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
		echo "enable_unseq_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
		echo "enable_cross_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
    elif [ "${server_kind}" = "small" ]; then
        #修改IoTDB的配置
		sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"4G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
		sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"2G\"/g" ${TEST_IOTDB_PATH}/conf/confignode-env.sh
		#关闭影响写入性能的其他功能
		echo "enable_seq_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
		echo "enable_unseq_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
		echo "enable_cross_space_compaction=false" >> ${TEST_IOTDB_PATH}/conf/iotdb-system.properties
	else
		echo "服务器类型错误！"
		return
	fi
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
	
	echo "测试开始！"
	rm -rf ${BM_PATH}/TestResult/*
	for (( i = 0; i < ${#query_list[*]}; i++ ))
	do
		#设置环境并启动IoTDB
		setup_env_q ${TEST_IP}
		for (( j = 1; j <= 2; j++ ))
		do
			echo "开始${query_list[${i}]}查询的第${j}次测试！"
			throughput_metrics=0
			throughput_rows=0
			query_rate=0
			MIN_NUM=0
			MED_NUM=0
			MEAN_NUM=0
			MAX_NUM=0
			STDDEV_NUM=0
			SUM_NUM=0 
			COUNT_NUM=0
			numOfSe0Level=0
			numOfUnse0Level=0
			start_time=0
			end_time=0
			cost_time=0
			dataFileSize=0
			maxNumofOpenFiles=0
			maxNumofThread=0
			errorLogSize=0
			round_num=${j}
			echo "查询测试开始！"
			start_time=`date -d today +"%Y-%m-%d %H:%M:%S"`
			m_start_time=$(date +%s)
			nohup cat ${BM_PATH}/iotdb-query-${query_list[${i}]}.txt | ${BM_PATH}/bin/tsbs_run_queries_iotdb --host="${TEST_IP}" --port="6667" --user="root" --password="root" --workers=100 --print-responses=false > ${BM_PATH}/TestResult/query_output_${query_list[${i}]}_${round_num}.log 2>&1 &
			#等待1分钟
			sleep 10
			monitor_test_status ${TEST_IP}
			#测试结果收集写入数据库
			#收集启动后基础监控数据
			m_end_time=$(date +%s)
			collect_monitor_data ${TEST_IP}
			Outputfile=${BM_PATH}/TestResult/query_output_${query_list[${i}]}_${round_num}.log
			read query_rate <<<$(cat ${Outputfile} | grep "complete"| sed -n '1,1p' | awk '{print $12}')
			read MIN_NUM MED_NUM MEAN_NUM MAX_NUM STDDEV_NUM SUM_NUM COUNT_NUM <<<$(cat ${Outputfile} | grep "min"| sed 's/ms//g' | sed 's/sec//g' | sed 's/,//g' | sed '$!d' | awk '{print $2,$4,$6,$8,$10,$12,$14}')
			insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,server_kind,throughput_metrics,throughput_rows,query_rate,MIN_NUM,MEAN_NUM,MED_NUM,MAX_NUM,STDDEV_NUM,SUM_NUM,COUNT_NUM,numOfSe0Level,numOfUnse0Level,start_time,end_time,cost_time,dataFileSize,maxNumofOpenFiles,maxNumofThread,errorLogSize,remark,walFileSize,avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,round_num) values(${commit_date_time},${test_date_time},'${commit_id}','${author}','${server_kind}',${throughput_metrics},${throughput_rows},${query_rate},${MIN_NUM},${MEAN_NUM},${MED_NUM},${MAX_NUM},${STDDEV_NUM},${SUM_NUM},${COUNT_NUM},${numOfSe0Level},${numOfUnse0Level},'${start_time}','${end_time}',${cost_time},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${errorLogSize},'${query_list[${i}]}',${walFileSize},${avgCPULoad},${maxCPULoad},${maxDiskIOSizeRead},${maxDiskIOSizeWrite},${maxDiskIOOpsRead},${maxDiskIOOpsWrite},${round_num})"
			echo "${insert_sql}"
			mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
			sleep 20
		done		
	done
	#query没有存下日志（只有最后一次）
	backup_test_data ${server_kind} ${TEST_IP} query
}

##准备开始测试
echo "ontesting" > ${INIT_PATH}/test_type_file
query_sql="SELECT commit_id,',',author,',',commit_date_time,',' FROM ${TASK_TABLENAME} WHERE ${test_type} is NULL ORDER BY commit_date_time desc limit 1 "
result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${query_sql}")
commit_id=$(echo $result_string| awk -F, '{print $4}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
author=$(echo $result_string| awk -F, '{print $5}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
commit_date_time=$(echo $result_string | awk -F, '{print $6}' | sed s/-//g | sed s/://g | sed s/[[:space:]]//g | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
if [ "${commit_id}" = "" ]; then
	sleep 60s
else
	update_sql="update ${TASK_TABLENAME} set ${test_type} = 'ontesting' where commit_id = '${commit_id}'"
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}")
	echo "当前版本${commit_id}未执行过测试，即将编译后启动"
	###############################写入###############################
	init_items
	test_date_time=`date +%Y%m%d%H%M%S`
	echo "开始测试中等配置！"
	test_operation medium ${Medium_IP} 223
	init_items
	test_date_time=`date +%Y%m%d%H%M%S`
	echo "开始测试小型配置！"
	test_operation small ${Small_IP} 223
	###############################查询###############################
	init_items
	test_date_time=`date +%Y%m%d%H%M%S`
	echo "开始测试中等配置！"
	test_operation_q medium ${Medium_IP} 223
	init_items
	test_date_time=`date +%Y%m%d%H%M%S`
	echo "开始测试小型配置！"
	test_operation_q small ${Small_IP} 223
	###############################测试完成###############################
	echo "本轮测试${test_date_time}已结束."
	update_sql="update ${TASK_TABLENAME} set ${test_type} = 'done' where commit_id = '${commit_id}'"
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}")
fi
echo "${test_type}" > ${INIT_PATH}/test_type_file