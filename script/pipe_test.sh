#!/bin/sh
#登录用户名
ACCOUNT=root
test_type=pipe_test
#初始环境存放路径
INIT_PATH=/root/zk_test
ATMOS_PATH=${INIT_PATH}/atmos-e
BM_PATH=${INIT_PATH}/iot-benchmark
BUCKUP_PATH=/nasdata/repository/pipe_test
REPOS_PATH=/nasdata/repository/master
#测试数据运行路径
TEST_INIT_PATH=/data/cluster/first-rest-test
TEST_IOTDB_PATH=${TEST_INIT_PATH}/apache-iotdb
TEST_BM_PATH=${TEST_INIT_PATH}/iot-benchmark
# 1. org.apache.iotdb.consensus.simple.SimpleConsensus
# 2. org.apache.iotdb.consensus.ratis.RatisConsensus
# 3. org.apache.iotdb.consensus.iot.IoTConsensus
protocol_class=(0 org.apache.iotdb.consensus.simple.SimpleConsensus org.apache.iotdb.consensus.ratis.RatisConsensus org.apache.iotdb.consensus.iot.IoTConsensus)
protocol_list=(223)
ts_list=(common aligned)
IP_list=(0 172.20.31.45 172.20.31.58)
PIPE_list=(0 172.20.31.58 172.20.31.45)
Control=172.20.31.51
config_node_config_nodes=(0 172.20.31.45:10710 172.20.31.58:10710)
data_node_config_nodes=(0 172.20.31.45:10710 172.20.31.58:10710)
############mysql信息##########################
MYSQLHOSTNAME="111.202.73.147" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD="iotdb2019"
DBNAME="QA_ATM"  #数据库名称
TABLENAME="test_result_pipe_test" #数据库中表的名称
TASK_TABLENAME="commit_history" #数据库中任务表的名称
############公用函数##########################
#echo "Started at: " date -d today +"%Y-%m-%d %H:%M:%S"
init_items() {
############定义监控采集项初始值##########################
test_date_time=0
ts_type=0
start_time=0
end_time=0
cost_time=0
wait_time=0
failPointA=0
throughputA=0
LatencyA=0
numOfSe0LevelA=0
numOfUnse0LevelA=0
dataFileSizeA=0
maxNumofOpenFilesA=0
maxNumofThreadA=0
errorLogSizeA=0
failPointB=0
throughputB=0
LatencyB=0
numOfSe0LevelB=0
numOfUnse0LevelB=0
dataFileSizeB=0
maxNumofOpenFilesB=0
maxNumofThreadB=0
errorLogSizeB=0
############定义监控采集项初始值##########################
}
local_ip=`ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"`
sendEmail() {
sendEmail=$(${TOOLS_PATH}/sendEmail.sh $1 >/dev/null 2>&1 &)
}
check_benchmark_pid() { # 检查benchmark的pid，有就停止
	monitor_pid=$(jps | grep App | awk '{print $1}')
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
	if [ ! -d "${TEST_INIT_PATH}" ]; then
		mkdir -p ${TEST_INIT_PATH}
	else
		rm -rf ${TEST_INIT_PATH}
		mkdir -p ${TEST_IOTDB_PATH}
	fi
	cp -rf ${REPOS_PATH}/${commit_id}/apache-iotdb/* ${TEST_IOTDB_PATH}/
	cp -rf ${BM_PATH} ${TEST_INIT_PATH}/
}
modify_iotdb_config() { # iotdb调整内存，关闭合并
	#修改IoTDB的配置
	sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"20G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
	sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"6G\"/g" ${TEST_IOTDB_PATH}/conf/confignode-env.sh
	sed -i "s/^# query_timeout_threshold=.*$/query_timeout_threshold=6000000/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	#关闭影响写入性能的其他功能
	sed -i "s/^# enable_seq_space_compaction=true.*$/enable_seq_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^# enable_unseq_space_compaction=true.*$/enable_unseq_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^# enable_cross_space_compaction=true.*$/enable_cross_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	#修改集群名称
	sed -i "s/^cluster_name=.*$/cluster_name=${test_type}/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	#开启自动创建
	sed -i "s/^# enable_auto_create_schema=.*$/enable_auto_create_schema=true/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^# default_storage_group_level=.*$/default_storage_group_level=2/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	#添加启动监控功能
	sed -i "s/^# cn_enable_metric=.*$/cn_enable_metric=true/g" ${TEST_IOTDB_PATH}/conf/iotdb-confignode.properties
	sed -i "s/^# cn_enable_performance_stat=.*$/cn_enable_performance_stat=true/g" ${TEST_IOTDB_PATH}/conf/iotdb-confignode.properties
	sed -i "s/^# cn_metric_reporter_list=.*$/cn_metric_reporter_list=PROMETHEUS/g" ${TEST_IOTDB_PATH}/conf/iotdb-confignode.properties
	sed -i "s/^# cn_metric_level=.*$/cn_metric_level=ALL/g" ${TEST_IOTDB_PATH}/conf/iotdb-confignode.properties
	sed -i "s/^# cn_metric_prometheus_reporter_port=.*$/cn_metric_prometheus_reporter_port=9081/g" ${TEST_IOTDB_PATH}/conf/iotdb-confignode.properties
	#添加启动监控功能
	sed -i "s/^# dn_enable_metric=.*$/dn_enable_metric=true/g" ${TEST_IOTDB_PATH}/conf/iotdb-datanode.properties
	sed -i "s/^# dn_enable_performance_stat=.*$/dn_enable_performance_stat=true/g" ${TEST_IOTDB_PATH}/conf/iotdb-datanode.properties
	sed -i "s/^# dn_metric_reporter_list=.*$/dn_metric_reporter_list=PROMETHEUS/g" ${TEST_IOTDB_PATH}/conf/iotdb-datanode.properties
	sed -i "s/^# dn_metric_level=.*$/dn_metric_level=ALL/g" ${TEST_IOTDB_PATH}/conf/iotdb-datanode.properties
	sed -i "s/^# dn_metric_prometheus_reporter_port=.*$/dn_metric_prometheus_reporter_port=9091/g" ${TEST_IOTDB_PATH}/conf/iotdb-datanode.properties
}
set_protocol_class() { 
	config_node=$1
	schema_region=$2
	data_region=$3
	#设置协议
	sed -i "s/^# config_node_consensus_protocol_class=.*$/config_node_consensus_protocol_class=${protocol_class[${config_node}]}/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^# schema_region_consensus_protocol_class=.*$/schema_region_consensus_protocol_class=${protocol_class[${schema_region}]}/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^# data_region_consensus_protocol_class=.*$/data_region_consensus_protocol_class=${protocol_class[${data_region}]}/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
}
setup_env() {
	echo "开始重置环境！"
	for (( j = 1; j < ${#IP_list[*]}; j++ ))
	do
		TEST_IP=${IP_list[$j]}
		ssh ${ACCOUNT}@${TEST_IP} "sudo reboot"
	done
	sleep 60
	for (( i = 1; i < ${#IP_list[*]}; i++ ))
	do
		echo "开始部署${IP_list[$i]}！"
		TEST_IP=${IP_list[$i]}
		echo "setting env to ${TEST_IP} ..."
		#删除原有路径下所有
		ssh ${ACCOUNT}@${TEST_IP} "rm -rf ${TEST_INIT_PATH}"
		ssh ${ACCOUNT}@${TEST_IP} "mkdir -p ${TEST_INIT_PATH}"
		#修改IoTDB的配置
		sed -i "s/^dn_rpc_address.*$/dn_rpc_address=${TEST_IP}/g" ${TEST_IOTDB_PATH}/conf/iotdb-datanode.properties
		sed -i "s/^dn_internal_address.*$/dn_internal_address=${TEST_IP}/g" ${TEST_IOTDB_PATH}/conf/iotdb-datanode.properties
		sed -i "s/^dn_seed_config_node.*$/dn_seed_config_node=${data_node_config_nodes[$i]}/g" ${TEST_IOTDB_PATH}/conf/iotdb-datanode.properties
		sed -i "s/^cn_internal_address.*$/cn_internal_address=${TEST_IP}/g" ${TEST_IOTDB_PATH}/conf/iotdb-confignode.properties
		sed -i "s/^cn_seed_config_node.*$/cn_seed_config_node=${config_node_config_nodes[$i]}/g" ${TEST_IOTDB_PATH}/conf/iotdb-confignode.properties
		#准备配置文件和license
		mv_config_file ${ts_type} ${TEST_IP}
		#sed -i "s/^HOST=.*$/HOST=${TEST_IP}/g" ${TEST_BM_PATH}/conf/config.properties
		rm -rf ${TEST_INIT_PATH}/apache-iotdb/activation
		mkdir -p ${TEST_INIT_PATH}/apache-iotdb/activation
		cp -rf ${ATMOS_PATH}/conf/${test_type}/${TEST_IP} ${TEST_INIT_PATH}/apache-iotdb/activation/license
		#复制三项到客户机
		scp -r ${TEST_INIT_PATH}/* ${ACCOUNT}@${TEST_IP}:${TEST_INIT_PATH}/
		#scp -r ${TEST_INIT_PATH}/* ${ACCOUNT}@${TEST_IP}:${TEST_INIT_PATH}/  > /dev/null 2>&1 &
	done	
	sleep 3
	for (( i = 1; i < ${#IP_list[*]}; i++ ))
	do
		TEST_IP=${IP_list[$i]}
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
	done
	sleep 3
	for (( i = 1; i < ${#IP_list[*]}; i++ ))
	do
		TEST_IP=${IP_list[$i]}
		str1=$(ssh ${ACCOUNT}@${TEST_IP} "${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${TEST_IP} -p 6667 -u root -pw root -e \"create pipe test with source ('source.pattern'='root', 'source.realtime.mode'='stream','source.realtime.enable'='true','source.forwarding-pipe-requests'='false','source.batch.enable'='true','source.history.enable'='true') with sink ('sink'='iotdb-thrift-sink', 'sink.node-urls'='${PIPE_list[$i]}:6667');\"")
		echo $str1
		str1=$(ssh ${ACCOUNT}@${TEST_IP} "${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${TEST_IP} -p 6667 -u root -pw root -e \"start pipe test;\"")
		echo $str1
	done		
}
monitor_test_status() { # 监控测试运行状态，获取最大打开文件数量和最大线程数
	TEST_IP=$1
	maxNumofOpenFilesA=0
	maxNumofThreadA=0
	maxNumofOpenFilesB=0
	maxNumofThreadB=0
	while true; do
		for (( j = 1; j < ${#IP_list[*]}; j++ ))
		do
			TEST_IP=${IP_list[$j]}
			temp_file_num_d=0
			temp_thread_num_d=0
			temp_file_num_c=0
			temp_thread_num_c=0
			dn_pid=$(ssh ${ACCOUNT}@${TEST_IP} "jps | grep DataNode | awk '{print $1}'")
			cn_pid=$(ssh ${ACCOUNT}@${TEST_IP} "jps | grep ConfigNode | awk '{print $1}'")
			if [ "$dn_pid" = "" ] && [ "${cn_pid}" = "" ]; then
				temp_file_num_d=0
				temp_thread_num_d=0
				temp_file_num_c=0
				temp_thread_num_c=0
			elif [ "$dn_pid" = "" ] && [ "${cn_pid}" != "" ]; then
				temp_file_num_d=0
				temp_thread_num_d=0
				temp_thread_num_c=$(ssh ${ACCOUNT}@${TEST_IP} "pstree -p \$(ps aux | grep -v grep | grep ConfigNode | awk '{print \$2}') | wc -l" 2>/dev/null)
				temp_file_num_c=$(ssh ${ACCOUNT}@${TEST_IP} "ps aux | grep -v grep | grep ConfigNode | awk '{print \$2}' | xargs /usr/sbin/lsof -p | wc -l" 2>/dev/null)
			elif [ "$dn_pid" != "" ] && [ "${cn_pid}" = "" ]; then
				temp_thread_num_d=$(ssh ${ACCOUNT}@${TEST_IP} "pstree -p \$(ps aux | grep -v grep | grep DataNode | awk '{print \$2}') | wc -l" 2>/dev/null)
				temp_file_num_d=$(ssh ${ACCOUNT}@${TEST_IP} "ps aux | grep -v grep | grep DataNode | awk '{print \$2}' | xargs /usr/sbin/lsof -p | wc -l" 2>/dev/null)
				temp_file_num_c=0
				temp_thread_num_c=0
			elif [ "$dn_pid" != "" ] && [ "${cn_pid}" != "" ]; then
				temp_thread_num_d=$(ssh ${ACCOUNT}@${TEST_IP} "pstree -p \$(ps aux | grep -v grep | grep DataNode | awk '{print \$2}') | wc -l" 2>/dev/null)
				temp_file_num_d=$(ssh ${ACCOUNT}@${TEST_IP} "ps aux | grep -v grep | grep DataNode | awk '{print \$2}' | xargs /usr/sbin/lsof -p | wc -l" 2>/dev/null)
				temp_thread_num_c=$(ssh ${ACCOUNT}@${TEST_IP} "pstree -p \$(ps aux | grep -v grep | grep ConfigNode | awk '{print \$2}') | wc -l" 2>/dev/null)
				temp_file_num_c=$(ssh ${ACCOUNT}@${TEST_IP} "ps aux | grep -v grep | grep ConfigNode | awk '{print \$2}' | xargs /usr/sbin/lsof -p | wc -l" 2>/dev/null)
			else
				echo "无法计算！"
			fi
			if [ "${TEST_IP}" = "${IP_list[1]}" ]; then
				#监控打开文件数量			
				let temp_file_num=${temp_file_num_d}+${temp_file_num_c}
				if [ ${maxNumofOpenFilesA} -lt ${temp_file_num} ]; then
					maxNumofOpenFilesA=${temp_file_num}
				fi
				#监控线程数
				let temp_thread_num=${temp_thread_num_d}+${temp_thread_num_c}
				if [ ${maxNumofThreadA} -lt ${temp_thread_num} ]; then
					maxNumofThreadA=${temp_thread_num}
				fi
			else
				#监控打开文件数量			
				let temp_file_num=${temp_file_num_d}+${temp_file_num_c}
				if [ ${maxNumofOpenFilesB} -lt ${temp_file_num} ]; then
					maxNumofOpenFilesB=${temp_file_num}
				fi
				#监控线程数
				let temp_thread_num=${temp_thread_num_d}+${temp_thread_num_c}
				if [ ${maxNumofThreadB} -lt ${temp_thread_num} ]; then
					maxNumofThreadB=${temp_thread_num}
				fi
			fi
		done
		now_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
		t_time=$(($(date +%s -d "${now_time}") - $(date +%s -d "${start_time}")))
		if [ $t_time -ge 600 ]; then
			#前半小时不进行判定
			#确认是否测试已结束
			flag=0
			str1=$(ssh ${ACCOUNT}@${IP_list[1]} "${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${IP_list[1]} -p 6667 -u root -pw root -e \"select count(*) from root.test.g_0.*\" | grep -o '172800' | wc -l ")
			str2=$(ssh ${ACCOUNT}@${IP_list[2]} "${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${IP_list[2]} -p 6667 -u root -pw root -e \"select count(*) from root.test.g_0.*\" | grep -o '172800' | wc -l ")
			#str2=$(ssh ${ACCOUNT}@${IP_list[2]} "${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${IP_list[2]} -p 6667 -u root -pw root -e \"select count(*) from root.test.g_0.d_${d}\" | grep -o '172800' | wc -l ")
			if [ "$str1" = "25000" ] && [ "$str2" = "25000" ]; then
				echo "root.test.g_0同步已结束"
				flag=$[${flag}+1]
			else
				#echo "同步未结束:${Control}"  > /dev/null 2>&1 &
				echo "同步未结束:${Control}"
			fi
			now_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
			t_time=$(($(date +%s -d "${now_time}") - $(date +%s -d "${start_time}")))
			if [ $t_time -ge 7200 ]; then
				echo "测试失败"  #倒序输入形成负数结果
				end_time=-1
				cost_time=-1
				break [2]
			fi
			echo $flag
			if [ "$flag" = "1" ]; then
				end_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
				cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
				break
			fi
		fi
	done
}
collect_monitor_data() { # 收集iotdb数据大小，顺、乱序文件数量
	for (( j = 1; j < ${#IP_list[*]}; j++ ))
	do
		TEST_IP=${IP_list[$j]}	
		dataFileSizeA=0
		numOfSe0LevelA=0
		numOfUnse0LevelA=0
		dataFileSizeB=0
		numOfSe0LevelB=0
		numOfUnse0LevelB=0
		if [ "${TEST_IP}" = "${IP_list[1]}" ]; then
			dataFileSizeA=$(ssh ${ACCOUNT}@${TEST_IP} "du -h -d0 ${TEST_IOTDB_PATH}/data/datanode/data | awk {'print \$1'} | awk '{sub(/.$/,\"\")}1'")
			UNIT=$(ssh ${ACCOUNT}@${TEST_IP} "du -h -d0 ${TEST_IOTDB_PATH}/data/datanode/data | awk {'print \$1'} | awk -F '' '\$0=\$NF'")
			if [ "$UNIT" = "M" ]; then
				dataFileSizeA=`awk 'BEGIN{printf "%.2f\n",'$dataFileSizeA'/'1024'}'`
			elif [ "$UNIT" = "K" ]; then
				dataFileSizeA=`awk 'BEGIN{printf "%.2f\n",'$dataFileSizeA'/'1048576'}'`
			elif [ "$UNIT" = "T" ]; then
				dataFileSizeA=`awk 'BEGIN{printf "%.2f\n",'$dataFileSizeA'*'1024'}'`
			else
				dataFileSizeA=${dataFileSizeA}
			fi	
			numOfSe0LevelA=$(ssh ${ACCOUNT}@${TEST_IP} "find ${TEST_IOTDB_PATH}/data/datanode/data/sequence -name "*.tsfile" | wc -l")
			numOfUnse0LevelA=$(ssh ${ACCOUNT}@${TEST_IP} "find ${TEST_IOTDB_PATH}/data/datanode/data/unsequence -name "*.tsfile" | wc -l")
		else
			dataFileSizeB=$(ssh ${ACCOUNT}@${TEST_IP} "du -h -d0 ${TEST_IOTDB_PATH}/data/datanode/data | awk {'print \$1'} | awk '{sub(/.$/,\"\")}1'")
			UNIT=$(ssh ${ACCOUNT}@${TEST_IP} "du -h -d0 ${TEST_IOTDB_PATH}/data/datanode/data | awk {'print \$1'} | awk -F '' '\$0=\$NF'")
			if [ "$UNIT" = "M" ]; then
				dataFileSizeB=`awk 'BEGIN{printf "%.2f\n",'$dataFileSizeB'/'1024'}'`
			elif [ "$UNIT" = "K" ]; then
				dataFileSizeB=`awk 'BEGIN{printf "%.2f\n",'$dataFileSizeB'/'1048576'}'`
			elif [ "$UNIT" = "T" ]; then
				dataFileSizeB=`awk 'BEGIN{printf "%.2f\n",'$dataFileSizeB'*'1024'}'`
			else
				dataFileSizeB=${dataFileSizeB}
			fi	
			numOfSe0LevelB=$(ssh ${ACCOUNT}@${TEST_IP} "find ${TEST_IOTDB_PATH}/data/datanode/data/sequence -name "*.tsfile" | wc -l")
			numOfUnse0LevelB=$(ssh ${ACCOUNT}@${TEST_IP} "find ${TEST_IOTDB_PATH}/data/datanode/data/unsequence -name "*.tsfile" | wc -l")
		fi
	done
}
backup_test_data() { # 备份测试数据
	TEST_IP=$2
	sudo mkdir -p ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}/$3
	str1=$(ssh ${ACCOUNT}@${TEST_IP} "rm -rf ${TEST_IOTDB_PATH}/data" 2>/dev/null)
	scp -r ${ACCOUNT}@${TEST_IP}:${TEST_IOTDB_PATH}/ ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}/$3
	sudo cp -rf ${BM_PATH}/TestResult/ ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}/$3
}
mv_config_file() { # 移动配置文件
	rm -rf ${TEST_BM_PATH}/conf/config.properties
	cp -rf ${ATMOS_PATH}/conf/${test_type}/$1/$2 ${TEST_BM_PATH}/conf/config.properties
}
clear_expired_file() { # 清理超过七天的文件
	find $1 -mtime +7 -type d -name "*" -exec rm -rf {} \;
}
test_operation() {
	protocol_class=$1
	ts_type=$2
	echo "开始测试${ts_type}时间序列！"
	#复制当前程序到执行位置
	set_env
	#修改IoTDB的配置
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
	#启动iotdb
	setup_env
	sleep 10
	#启动写入程序
	for (( j = 1; j < ${#IP_list[*]}; j++ ))
	do
		TEST_IP=${IP_list[$j]}
		echo "开始写入！"
		pid3=$(ssh ${ACCOUNT}@${TEST_IP} "${TEST_BM_PATH}/benchmark.sh > /dev/null 2>&1 &")
	done
	start_time=`date -d today +"%Y-%m-%d %H:%M:%S"`

	#等待1分钟
	sleep 60
	monitor_test_status
	#收集启动后基础监控数据
	collect_monitor_data
	#测试结果收集写入数据库
	for ((j = 1; j < ${#IP_list[*]}; j++)); do
		rm -rf ${TEST_BM_PATH}/TestResult/csvOutput/*
		scp -r ${ACCOUNT}@${IP_list[${j}]}:${TEST_BM_PATH}/data/csvOutput/*result.csv ${TEST_BM_PATH}/TestResult/csvOutput/
		#收集启动后基础监控数据
		csvOutputfile=${TEST_BM_PATH}/TestResult/csvOutput/*result.csv
		if [ ! -f $csvOutputfile ]; then
			okOperation=0
			okPoint=0
			failOperation=0
			failPoint=0
			throughput=0
		else
			if [ j -eq 1 ]; then
				read okOperationA okPointA failOperationA failPointA throughputA <<<$(cat ${csvOutputfile} | grep ^INGESTION | sed -n '1,1p' | awk -F, '{print $2,$3,$4,$5,$6}')
				read LatencyA MIN P10 P25 MEDIAN P75 P90 P95 P99 P999 MAX <<<$(cat ${csvOutputfile} | grep ^INGESTION | sed -n '2,2p' | awk -F, '{print $2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12}')
			else
				read okOperationB okPointB failOperationB failPointB throughputB <<<$(cat ${csvOutputfile} | grep ^INGESTION | sed -n '1,1p' | awk -F, '{print $2,$3,$4,$5,$6}')
				read LatencyB MIN P10 P25 MEDIAN P75 P90 P95 P99 P999 MAX <<<$(cat ${csvOutputfile} | grep ^INGESTION | sed -n '2,2p' | awk -F, '{print $2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12}')
			fi
		fi
	done	
	cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
	insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,ts_type,start_time,end_time,cost_time,wait_time,failPointA,throughputA,LatencyA,numOfSe0LevelA,numOfUnse0LevelA,dataFileSizeA,maxNumofOpenFilesA,maxNumofThreadA,errorLogSizeA,failPointB,throughputB,LatencyB,numOfSe0LevelB,numOfUnse0LevelB,dataFileSizeB,maxNumofOpenFilesB,maxNumofThreadB,errorLogSizeB,remark) values(${commit_date_time},${test_date_time},'${commit_id}','${author}','${ts_type}','${start_time}','${end_time}',${cost_time},${wait_time},${failPointA},${throughputA},${LatencyA},${numOfSe0LevelA},${numOfUnse0LevelA},${dataFileSizeA},${maxNumofOpenFilesA},${maxNumofThreadA},${errorLogSizeA},${failPointB},${throughputB},${LatencyB},${numOfSe0LevelB},${numOfUnse0LevelB},${dataFileSizeB},${maxNumofOpenFilesB},${maxNumofThreadB},${errorLogSizeB},${protocol_class})"

	mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"

	#备份本次测试
	backup_test_data ${ts_type}
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
	init_items
	test_date_time=`date +%Y%m%d%H%M%S`	
	for (( j = 0; j < ${#protocol_list[*]}; j++ ))
	do
		for (( i = 0; i < ${#ts_list[*]}; i++ ))
		do
			echo "开始测试${protocol_list[$j]}协议下的${ts_list[$i]}时间序列！"
			test_operation ${protocol_list[$j]} ${ts_list[$i]}
		done
	done	
	###############################测试完成###############################
	echo "本轮测试${test_date_time}已结束."
	update_sql="update ${TASK_TABLENAME} set ${test_type} = 'done' where commit_id = '${commit_id}'"
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}")
fi
echo "${test_type}" > ${INIT_PATH}/test_type_file