#!/bin/sh
#登录用户名
ACCOUNT=root
test_type=compaction
#初始环境存放路径
INIT_PATH=/root/zk_test
ATMOS_PATH=${INIT_PATH}/atmos-e
BM_PATH=${INIT_PATH}/iot-benchmark
DATA_PATH=/nasdata/compaction/DataSet
BUCKUP_PATH=/nasdata/repository/compaction
REPOS_PATH=/nasdata/repository/master
#测试数据运行路径
TEST_INIT_PATH=/data/qa
TEST_IOTDB_PATH=${TEST_INIT_PATH}/apache-iotdb
# 1. org.apache.iotdb.consensus.simple.SimpleConsensus
# 2. org.apache.iotdb.consensus.ratis.RatisConsensus
# 3. org.apache.iotdb.consensus.iot.IoTConsensus
protocol_class=(0 org.apache.iotdb.consensus.simple.SimpleConsensus org.apache.iotdb.consensus.ratis.RatisConsensus org.apache.iotdb.consensus.iot.IoTConsensus)
protocol_list=(111 223 222 211)
#ts_list=(common aligned template tempaligned)
ts_list=(common aligned)
############mysql信息##########################
MYSQLHOSTNAME="111.202.73.147" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD="iotdb2019"
DBNAME="QA_ATM"  #数据库名称
TABLENAME="test_result_compaction" #数据库中表的名称
TASK_TABLENAME="commit_history" #数据库中任务表的名称
############公用函数##########################
#echo "Started at: " date -d today +"%Y-%m-%d %H:%M:%S"
init_items() {
############定义监控采集项初始值##########################
test_date_time=0
ts_type=0
cost_time=0
numOfSe0Level_before=0
numOfSe0Level_after=0
numOfUnse0Level_before=0
numOfUnse0Level_after=0
ts_dataSize=0
ts_numOfPoints=0
compaction_rate=0
comp_start_time=0
comp_end_time=0
dataFileSize_before=0
dataFileSize_after=0
maxNumofOpenFiles=0
maxNumofThread=0
errorLogSize=0
############定义监控采集项初始值##########################
}
local_ip=`ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"`
sendEmail() {
sendEmail=$(${TOOLS_PATH}/sendEmail.sh $1 >/dev/null 2>&1 &)
}
check_benchmark_pid() { # 检查benchmark-moitor的pid，有就停止
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
	if [ ! -d "${TEST_IOTDB_PATH}" ]; then
		mkdir -p ${TEST_IOTDB_PATH}
	else
		rm -rf ${TEST_IOTDB_PATH}
		mkdir -p ${TEST_IOTDB_PATH}
	fi
	cp -rf ${REPOS_PATH}/${commit_id}/apache-iotdb/* ${TEST_IOTDB_PATH}/
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
modify_iotdb_config() { # iotdb调整内存，关闭合并
	#修改IoTDB的配置
	sed -i "s/^#MAX_HEAP_SIZE=\"2G\".*$/MAX_HEAP_SIZE=\"20G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
	#关闭影响写入性能的其他功能
	sed -i "s/^# enable_seq_space_compaction=true.*$/enable_seq_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^# enable_unseq_space_compaction=true.*$/enable_unseq_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^# enable_cross_space_compaction=true.*$/enable_cross_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
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
start_iotdb() { # 启动iotdb
	cd ${TEST_IOTDB_PATH}
	conf_start=$(./sbin/start-confignode.sh >/dev/null 2>&1 &)
	sleep 10
	data_start=$(./sbin/start-datanode.sh >/dev/null 2>&1 &)
	cd ~/
}
start_benchmark() { # 启动benchmark
	cd ${BM_PATH}
	if [ -d "${BM_PATH}/logs" ]; then
		rm -rf ${BM_PATH}/logs
	fi
	if [ ! -d "${BM_PATH}/data" ]; then
		bm_start=$(${BM_PATH}/benchmark.sh >/dev/null 2>&1 &)
	else
		rm -rf ${BM_PATH}/data
		bm_start=$(${BM_PATH}/benchmark.sh >/dev/null 2>&1 &)
	fi
	cd ~/
}
monitor_test_status() { # 监控测试运行状态，获取最大打开文件数量和最大线程数
	start_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
	maxNumofOpenFiles=0
	for (( t_wait = 0; t_wait <= 100; ))
	do
		#监控打开文件数量
		pid=$(jps | grep DataNode | awk '{print $1}')
		if [ "${pid}" = "" ]; then
			temp_file_num_d=0
			temp_thread_num_d=0
		else
			temp_file_num_d=$(jps | grep DataNode | awk '{print $1}' | xargs lsof -p | wc -l)
			temp_thread_num_d=$(pstree -p $(ps -e | grep DataNode | awk '{print $1}') | wc -l)
		fi
		pid=$(jps | grep ConfigNode | awk '{print $1}')
		if [ "${pid}" = "" ]; then
			temp_file_num_c=0
			temp_thread_num_c=0
		else
			temp_file_num_c=$(jps | grep ConfigNode | awk '{print $1}' | xargs lsof -p | wc -l)
			temp_thread_num_c=$(pstree -p $(ps -e | grep ConfigNode | awk '{print $1}') | wc -l)
		fi
		pid=$(jps | grep IoTDB | awk '{print $1}')
		if [ "${pid}" = "" ]; then
			temp_file_num_i=0
			temp_thread_num_i=0
		else
			temp_file_num_i=$(jps | grep IoTDB | awk '{print $1}' | xargs lsof -p | wc -l)
			temp_thread_num_i=$(pstree -p $(ps -e | grep IoTDB | awk '{print $1}') | wc -l)
		fi
		let temp_file_num=${temp_file_num_d}+${temp_file_num_c}+${temp_file_num_i}
		if [ ${maxNumofOpenFiles} -lt ${temp_file_num} ]; then
			maxNumofOpenFiles=${temp_file_num}
		fi
		#监控线程数
		let temp_thread_num=${temp_thread_num_d}+${temp_thread_num_c}+${temp_thread_num_i}
		if [ ${maxNumofThread} -lt ${temp_thread_num} ]; then
			maxNumofThread=${temp_thread_num}
		fi
		#监控合并执行情况  
		cd ${TEST_IOTDB_PATH}/data/datanode/data
		numOfcompactioning=$(find . -name "*compaction.log" | wc -l)
		compaction_status=0
		if [ ${numOfcompactioning} -le 0 ]; then
			sleep 70s
			numOfcompactioning=$(find . -name "*compaction.log" | wc -l)
			if [ ${numOfcompactioning} -le 0 ]; then
				log_compaction=${TEST_IOTDB_PATH}/logs/log_datanode_compaction.log
				if [ ! -f "$log_compaction" ]; then
					now_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
					t_time=$(($(date +%s -d "${now_time}") - $(date +%s -d "${start_time}")))
					if [ $t_time -ge 7200 ]; then
						echo "测试失败"  #倒序输入形成负数结果
						 str1="2022-11-27 16:36:57,753 [pool-21-IoTDB-Compaction-1] INFO  o.a.i.d.e.c.c.CrossSpaceCompactionTask:207 - root.test.g_0-1 [Compaction] CrossSpaceCompaction task finishes successfully, time cost is -1 s, compaction speed is 1.9099134471928962 MB/s"
						str2="2022-11-27 15:54:50,568 [pool-21-IoTDB-Compaction-1] INFO  o.a.i.d.e.c.i.InnerSpaceCompactionTask:239 - root.test.g_0-1 [Compaction] InnerSpaceCompaction task finishes successfully, target file is 1668674556813-1-1-0.tsfile,time cost is -1 s, compaction speed is 16.47907336936178 MB/s"
						echo ${str1} >>$log_compaction
						echo ${str2} >>$log_compaction						
						break
					fi
					continue
				else
					echo "${comp_type}合并已完成"
					break
				fi
			fi
		else
			log_compaction=${TEST_IOTDB_PATH}/logs/log_datanode_compaction.log
			now_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
			t_time=$(($(date +%s -d "${now_time}") - $(date +%s -d "${start_time}")))
			if [ $t_time -ge 7200 ]; then
				echo "测试失败"  #倒序输入形成负数结果
				str1="2022-11-27 16:36:57,753 [pool-21-IoTDB-Compaction-1] INFO  o.a.i.d.e.c.c.CrossSpaceCompactionTask:207 - root.test.g_0-1 [Compaction] CrossSpaceCompaction task finishes successfully, time cost is -1 s, compaction speed is 1.9099134471928962 MB/s"
				str2="2022-11-27 15:54:50,568 [pool-21-IoTDB-Compaction-1] INFO  o.a.i.d.e.c.i.InnerSpaceCompactionTask:239 - root.test.g_0-1 [Compaction] InnerSpaceCompaction task finishes successfully, target file is 1668674556813-1-1-0.tsfile,time cost is -1 s, compaction speed is 16.47907336936178 MB/s"
				echo ${str1} >>$log_compaction
				echo ${str2} >>$log_compaction								
				break
			fi
			continue
		fi
	done
}
collect_data_before() { # 收集iotdb数据大小，顺、乱序文件数量
	cd ${TEST_IOTDB_PATH}
	dataFileSize_before=$(du -h -d0 ${TEST_IOTDB_PATH}/data | awk {'print $1'} | awk '{sub(/.$/,"")}1')
	UNIT=$(du -h -d0 ${TEST_IOTDB_PATH}/data | awk {'print $1'} | awk -F '' '$0=$NF')
	if [ "$UNIT" = "M" ]; then
		dataFileSize_before=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize_before'/'1024'}'`
	elif [ "$UNIT" = "K" ]; then
		dataFileSize_before=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize_before'/'1048576'}'`
	else
		dataFileSize_before=${dataFileSize_before}
	fi
	numOfSe0Level_before=$(find ${TEST_IOTDB_PATH}/data/datanode/data/sequence -name "*-0-*.tsfile" | wc -l)
	if [ ! -d "${TEST_IOTDB_PATH}/data/datanode/data/unsequence" ]; then
		numOfUnse0Level_before=0
	else
		#cd ${TEST_IOTDB_PATH}/data/datanode/data/unsequence
		numOfUnse0Level_before=$(find ${TEST_IOTDB_PATH}/data/datanode/data/unsequence -name "*-0-*.tsfile" | wc -l)
	fi
}
collect_data_after() { # 收集iotdb数据大小，顺、乱序文件数量
	#收集启动后基础监控数据
	cd ${TEST_IOTDB_PATH}
	dataFileSize_after=$(du -h -d0 ${TEST_IOTDB_PATH}/data | awk {'print $1'} | awk '{sub(/.$/,"")}1')
	UNIT=$(du -h -d0 ${TEST_IOTDB_PATH}/data | awk {'print $1'} | awk -F '' '$0=$NF')
	if [ "$UNIT" = "M" ]; then
		dataFileSize_after=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize_after'/'1024'}'`
	elif [ "$UNIT" = "K" ]; then
		dataFileSize_after=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize_after'/'1048576'}'`
	else
		dataFileSize_after=${dataFileSize_after}
	fi
	numOfSe0Level_after=$(find ${TEST_IOTDB_PATH}/data/datanode/data/sequence -name "*-0-*.tsfile" | wc -l)
	if [ ! -d "${TEST_IOTDB_PATH}/data/datanode/data/unsequence" ]; then
		numOfUnse0Level_after=0
	else
		#cd ${TEST_IOTDB_PATH}/data/datanode/data/unsequence
		numOfUnse0Level_after=$(find ${TEST_IOTDB_PATH}/data/datanode/data/unsequence -name "*-0-*.tsfile" | wc -l)
	fi
	compaction_rate=0
	ts_dataSize=0
	ts_numOfPoints=0
	#测试结果写入数据库
	comp_start_time=$(awk 'NR==1{print $1,$2}' ${TEST_IOTDB_PATH}/logs/log_datanode_compaction.log| cut -c 1-19)
	comp_end_time=$(awk 'END{print $1,$2}' ${TEST_IOTDB_PATH}/logs/log_datanode_compaction.log| cut -c 1-19)
	#cost_time=$(($(date +%s -d "${comp_end_time}") - $(date +%s -d "${comp_start_time}")))
	cd ${TEST_IOTDB_PATH}/logs/
	#cost_time=$(find ./* -name log_datanode_compaction.log | xargs grep "InnerSpaceCompaction task finishes successfully" | awk '{print $20}')
	var=$(find ./* -name log_datanode_compaction.log | xargs grep "InnerSpaceCompaction task finishes successfully")
	substring="time cost is"
	cost_time=$(echo ${var#*${substring}*} | awk -F" " '{print $1}')
	if [ "$cost_time" = "" ]; then
		#cost_time=$(find ./* -name log_datanode_compaction.log | xargs grep "CrossSpaceCompaction task finishes successfully" | awk '{print $16}')
		var=$(find ./* -name log_datanode_compaction.log | xargs grep "CrossSpaceCompaction task finishes successfully")
		substring="time cost is"
        	cost_time=$(echo ${var#*${substring}*} | awk -F" " '{print $1}')

	fi
	D_ErrorLogSize=$(du -sh ${TEST_IOTDB_PATH}/logs/log_datanode_error.log | awk {'print $1'})
	C_ErrorLogSize=$(du -sh ${TEST_IOTDB_PATH}/logs/log_confignode_error.log | awk {'print $1'})
	if [ "${D_ErrorLogSize}" = "0" ] && [ "${C_ErrorLogSize}" = "0" ]; then
		ErrorLogSize=0
	else
		ErrorLogSize=1
	fi
}
insert_database() { # 收集iotdb数据大小，顺、乱序文件数量
	#收集启动后基础监控数据
	remark_value=$1
	insert_sql="insert into ${TABLENAME}\
	(commit_date_time,test_date_time,commit_id,author,ts_type,comp_type,cost_time,numOfSe0Level_before,numOfSe0Level_after,\
	numOfUnse0Level_before,numOfUnse0Level_after,ts_dataSize,ts_numOfPoints,\
	compaction_rate,comp_start_time,comp_end_time,dataFileSize_before,dataFileSize_after,maxNumofOpenFiles,maxNumofThread,errorLogSize,remark) \
	values(${commit_date_time},${test_date_time},'${commit_id}','${author}','${ts_type}','${comp_type}',${cost_time},${numOfSe0Level_before},\
	${numOfSe0Level_after},${numOfUnse0Level_before},${numOfUnse0Level_after},\
	${ts_dataSize},${ts_numOfPoints},${compaction_rate},'${comp_start_time}',\
	'${comp_end_time}','${dataFileSize_before}','${dataFileSize_after}',${maxNumofOpenFiles},${maxNumofThread},${errorLogSize},'${remark_value}')"
	echo ${ts_type}时间序列 ${comp_type} 合并耗时为：${cost_time} 秒
	mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
	echo ${insert_sql}
}
backup_test_data() { # 备份测试数据
	sudo mkdir -p ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}
    sudo rm -rf ${TEST_IOTDB_PATH}/data
	sudo mv ${TEST_IOTDB_PATH} ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}
	sudo cp -rf ${BM_PATH}/data/csvOutput ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}
}
clear_expired_file() { # 清理超过七天的文件
	find $1 -mtime +7 -type d -name "*" -exec rm -rf {} \;
}
test_operation() {
	protocol_class=$1
	ts_type=$2
	echo "开始测试${ts_type}时间序列！"
	#清理环境，确保无就程序影响
	check_iotdb_pid
	#复制当前程序到执行位置
	set_env
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
	#mkdir -p ${TEST_IOTDB_PATH}/data
	cp -rf ${DATA_PATH}/${protocol_class}/${ts_type}/data ${TEST_IOTDB_PATH}/
	mkdir -p ${TEST_IOTDB_PATH}/data/datanode/system/license
	cp -rf ${ATMOS_PATH}/conf/license/active.license ${TEST_IOTDB_PATH}/data/datanode/system/license/active.license
	###############################seq_space合并###############################
	comp_type=seq_space
	#修改IoTDB的配置
	sed -i "s/^#MAX_HEAP_SIZE=\"2G\".*$/MAX_HEAP_SIZE=\"20G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
	#关闭影响写入性能的其他功能
	sed -i "s/^# enable_seq_space_compaction=.*$/enable_seq_space_compaction=true/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^# enable_unseq_space_compaction=.*$/enable_unseq_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^# enable_cross_space_compaction=.*$/enable_cross_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	#收集启动前基础监控数据
	collect_data_before
	#启动iotdb和monitor监控
	start_iotdb
	sleep 10	
	####判断IoTDB是否正常启动
	iotdb_state=$(${TEST_IOTDB_PATH}/sbin/start-cli.sh -e "show version" | grep 'Total line number = 1')
        #iotdb_state='Total line number = 1'
	if [ "${iotdb_state}" = "Total line number = 1" ]; then
		echo "IoTDB正常启动，准备开始测试"
	else
		echo "IoTDB未能正常启动，写入负值测试结果！"
		cost_time=-3
		insert_database ${protocol_class}
		update_sql="update commit_history set ${test_type} = 'RError' where commit_id = '${commit_id}'"
		result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}")
		return
	fi
	
	#start_monitor
	data1=$(date +%Y_%m_%d_%H%M%S | cut -c 1-10)
	#等待30分钟
	sleep 30
	monitor_test_status
	#停止IoTDB程序和监控程序
	#check_monitor_pid
	check_iotdb_pid
	#收集启动后基础监控数据，并写入数据库
	collect_data_after
	insert_database ${protocol_class}
	if [ -d "${TEST_IOTDB_PATH}/logs" ]; then
	mkdir -p ${TEST_IOTDB_PATH}/${comp_type}
	cp -rf ${TEST_IOTDB_PATH}/data ${TEST_IOTDB_PATH}/${comp_type}
	cp -rf ${TEST_IOTDB_PATH}/conf ${TEST_IOTDB_PATH}/${comp_type}
	mv ${TEST_IOTDB_PATH}/logs ${TEST_IOTDB_PATH}/${comp_type}	
	fi
	#同步服务器监控数据到统一的表内
	#drop_monitor_table
	###############################unseq_space合并###############################
	comp_type=unseq_space
	#修改IoTDB的配置
	sed -i "s/^#MAX_HEAP_SIZE=\"2G\".*$/MAX_HEAP_SIZE=\"20G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
	#关闭影响写入性能的其他功能
	sed -i "s/^enable_seq_space_compaction=.*$/enable_seq_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^enable_unseq_space_compaction=.*$/enable_unseq_space_compaction=true/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^enable_cross_space_compaction=.*$/enable_cross_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	#收集启动前基础监控数据
	collect_data_before
	#启动iotdb和monitor监控
	start_iotdb
	#start_monitor
	data1=$(date +%Y_%m_%d_%H%M%S | cut -c 1-10)
	#等待30分钟
	sleep 30
	monitor_test_status
	#停止IoTDB程序和监控程序
	#check_monitor_pid
	check_iotdb_pid
	#收集启动后基础监控数据，并写入数据库
	collect_data_after
	insert_database ${protocol_class}
	if [ -d "${TEST_IOTDB_PATH}/logs" ]; then
	mkdir -p ${TEST_IOTDB_PATH}/${comp_type}
	cp -rf ${TEST_IOTDB_PATH}/data ${TEST_IOTDB_PATH}/${comp_type}
	cp -rf ${TEST_IOTDB_PATH}/conf ${TEST_IOTDB_PATH}/${comp_type}
	mv ${TEST_IOTDB_PATH}/logs ${TEST_IOTDB_PATH}/${comp_type}	
	fi
	###############################cross_space合并###############################
	comp_type=cross_space
	#修改IoTDB的配置
	sed -i "s/^#MAX_HEAP_SIZE=\"2G\".*$/MAX_HEAP_SIZE=\"20G\"/g" ${TEST_IOTDB_PATH}/conf/datanode-env.sh
	#关闭影响写入性能的其他功能
	sed -i "s/^enable_seq_space_compaction=.*$/enable_seq_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^enable_unseq_space_compaction=.*$/enable_unseq_space_compaction=false/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	sed -i "s/^enable_cross_space_compaction=.*$/enable_cross_space_compaction=true/g" ${TEST_IOTDB_PATH}/conf/iotdb-common.properties
	#收集启动前基础监控数据
	collect_data_before
	#启动iotdb和monitor监控
	start_iotdb
	#start_monitor
	data1=$(date +%Y_%m_%d_%H%M%S | cut -c 1-10)
	#等待30分钟
	sleep 30
	monitor_test_status
	#停止IoTDB程序和监控程序
	#check_monitor_pid
	check_iotdb_pid
	#收集启动后基础监控数据，并写入数据库
	collect_data_after
	insert_database ${protocol_class}
	if [ -d "${TEST_IOTDB_PATH}/logs" ]; then
		mkdir -p ${TEST_IOTDB_PATH}/${comp_type}
		cp -rf ${TEST_IOTDB_PATH}/data ${TEST_IOTDB_PATH}/${comp_type}
		cp -rf ${TEST_IOTDB_PATH}/conf ${TEST_IOTDB_PATH}/${comp_type}
		mv ${TEST_IOTDB_PATH}/logs ${TEST_IOTDB_PATH}/${comp_type}	
	fi
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
	echo "当前版本${commit_id}未执行过测试，即将编译后启动"
	init_items
	test_date_time=`date +%Y%m%d%H%M%S`
	p_index=$(($RANDOM % ${#protocol_list[*]}))
	t_index=$(($RANDOM % ${#ts_list[*]}))		
	#echo "开始测试${protocol_list[$p_index]}协议下的${ts_list[$t_index]}时间序列！"
	#test_operation ${protocol_list[$p_index]} ${ts_list[$t_index]}
	#echo "开始测试211协议下的${ts_list[$t_index]}时间序列！"
	#test_operation 211 ${ts_list[$t_index]}
	echo "开始测试211协议下的common时间序列！"
	test_operation 211 common
	echo "开始测试211协议下的aligned时间序列！"
	test_operation 211 aligned
	#echo "开始测试211协议下的template时间序列！"
	#test_operation 211 template
	#echo "开始测试211协议下的tempaligned时间序列！"
	#test_operation 211 tempaligned
	###############################测试完成###############################
	echo "本轮测试${test_date_time}已结束."
	update_sql="update commit_history set ${test_type} = 'done' where commit_id = '${commit_id}'"
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}")
fi
echo "${test_type}" > ${INIT_PATH}/test_type_file