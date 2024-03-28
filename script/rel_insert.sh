#!/bin/sh
#登录用户名
TEST_IP=172.20.31.00
ACCOUNT=root
test_type=rel_insert
#初始环境存放路径
INIT_PATH=/root/zk_test
ATMOS_PATH=${INIT_PATH}/atmos-e
IOTDB_PATH=${INIT_PATH}/timechodb
BM_PATH=${INIT_PATH}/iotdb-benchmark
MONITOR_PATH=${INIT_PATH}/monitor
DATA_PATH=/data/original
BUCKUP_PATH=/data/weeklytest
#测试数据运行路径
TEST_INIT_PATH=/data/qa
TEST_IOTDB_PATH=${TEST_INIT_PATH}/timechodb
TEST_DATANODE_PATH=${TEST_INIT_PATH}/timechodb
# 1. org.apache.iotdb.consensus.simple.SimpleConsensus
# 2. org.apache.iotdb.consensus.ratis.RatisConsensus
# 3. org.apache.iotdb.consensus.iot.IoTConsensus
protocol_class=(0 org.apache.iotdb.consensus.simple.SimpleConsensus org.apache.iotdb.consensus.ratis.RatisConsensus org.apache.iotdb.consensus.iot.IoTConsensus)
############mysql信息##########################
MYSQLHOSTNAME="111.200.37.158" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD="iotdb2019"
DBNAME="QA_ATM"  #数据库名称
TABLENAME="weeklytest_insert_rel10" #数据库中表的名称
SERVERTABLE="SERVER_MODE_weeklytest"
############prometheus##########################
metric_server="172.20.70.11"
insert_list=(seq_w unseq_w seq_rw unseq_rw)
query_data_type=(no_overflow is_overflow)
query_list=(Q1 Q2-1 Q2-2 Q2-3 Q3-1 Q3-2 Q3-3 Q4-a1 Q4-a2 Q4-a3 Q4-b1 Q4-b2 Q4-b3 Q5 Q6-1 Q6-2 Q6-3 Q7-1 Q7-2 Q7-3 Q7-4 Q8 Q9 Q10)
query_type=(PRECISE_POINT, TIME_RANGE, TIME_RANGE, TIME_RANGE, VALUE_RANGE, VALUE_RANGE, VALUE_RANGE, AGG_RANGE, AGG_RANGE, AGG_RANGE, AGG_RANGE, AGG_RANGE, AGG_RANGE, AGG_VALUE, AGG_RANGE_VALUE, AGG_RANGE_VALUE, AGG_RANGE_VALUE, GROUP_BY, GROUP_BY, GROUP_BY, GROUP_BY, LATEST_POINT, RANGE_QUERY_DESC, VALUE_RANGE_QUERY_DESC,)
############公用函数##########################
#echo "Started at: " date -d today +"%Y-%m-%d %H:%M:%S"
init_items() {
############定义监控采集项初始值##########################
test_date_time=0
ts_type=0
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
############定义监控采集项初始值##########################
}
local_ip=`ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"`
check_monitor_pid() { # 检查benchmark-moitor的pid，有就停止
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
	cp -rf ${IOTDB_PATH}/distribution/target/iotdb-enterprise-*-bin/iotdb-enterprise-*-bin/* ${TEST_IOTDB_PATH}/
	cp -rf ${INIT_PATH}/license/data ${TEST_IOTDB_PATH}/
	mkdir -p ${TEST_IOTDB_PATH}/activation
	cp -rf ${ATMOS_PATH}/conf/${test_type}/license ${TEST_IOTDB_PATH}/activation/	
}
modify_iotdb_config() { # iotdb调整内存，关闭合并
	#修改IoTDB的配置
	sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"20G\"/g" ${TEST_DATANODE_PATH}/conf/datanode-env.sh
	#关闭影响写入性能的其他功能
	sed -i "s/^# enable_seq_space_compaction=true.*$/enable_seq_space_compaction=false/g" ${TEST_DATANODE_PATH}/conf/iotdb-common.properties
	sed -i "s/^# enable_unseq_space_compaction=true.*$/enable_unseq_space_compaction=false/g" ${TEST_DATANODE_PATH}/conf/iotdb-common.properties
	sed -i "s/^# enable_cross_space_compaction=true.*$/enable_cross_space_compaction=false/g" ${TEST_DATANODE_PATH}/conf/iotdb-common.properties
	#添加启动监控功能
	sed -i "s/^# cn_enable_metric=.*$/cn_enable_metric=true/g" ${TEST_DATANODE_PATH}/conf/iotdb-confignode.properties
	sed -i "s/^# cn_enable_performance_stat=.*$/cn_enable_performance_stat=true/g" ${TEST_DATANODE_PATH}/conf/iotdb-confignode.properties
	sed -i "s/^# cn_metric_reporter_list=.*$/cn_metric_reporter_list=PROMETHEUS/g" ${TEST_DATANODE_PATH}/conf/iotdb-confignode.properties
	sed -i "s/^# cn_metric_level=.*$/cn_metric_level=ALL/g" ${TEST_DATANODE_PATH}/conf/iotdb-confignode.properties
	sed -i "s/^# cn_metric_prometheus_reporter_port=.*$/cn_metric_prometheus_reporter_port=9081/g" ${TEST_DATANODE_PATH}/conf/iotdb-confignode.properties
	#添加启动监控功能
	sed -i "s/^# dn_enable_metric=.*$/dn_enable_metric=true/g" ${TEST_DATANODE_PATH}/conf/iotdb-datanode.properties
	sed -i "s/^# dn_enable_performance_stat=.*$/dn_enable_performance_stat=true/g" ${TEST_DATANODE_PATH}/conf/iotdb-datanode.properties
	sed -i "s/^# dn_metric_reporter_list=.*$/dn_metric_reporter_list=PROMETHEUS/g" ${TEST_DATANODE_PATH}/conf/iotdb-datanode.properties
	sed -i "s/^# dn_metric_level=.*$/dn_metric_level=ALL/g" ${TEST_DATANODE_PATH}/conf/iotdb-datanode.properties
	sed -i "s/^dn_metric_prometheus_reporter_port=.*$/dn_metric_prometheus_reporter_port=9091/g" ${TEST_DATANODE_PATH}/conf/iotdb-datanode.properties
	#sed -i '$a dn_metric_internal_reporter_type=MEMORY' ${TEST_DATANODE_PATH}/conf/iotdb-datanode.properties
}
set_protocol_class() { 
	config_node=$1
	schema_region=$2
	data_region=$3
	#设置协议
	sed -i "s/^# config_node_consensus_protocol_class=.*$/config_node_consensus_protocol_class=${protocol_class[${config_node}]}/g" ${TEST_DATANODE_PATH}/conf/iotdb-common.properties
	sed -i "s/^# schema_region_consensus_protocol_class=.*$/schema_region_consensus_protocol_class=${protocol_class[${schema_region}]}/g" ${TEST_DATANODE_PATH}/conf/iotdb-common.properties
	sed -i "s/^# data_region_consensus_protocol_class=.*$/data_region_consensus_protocol_class=${protocol_class[${data_region}]}/g" ${TEST_DATANODE_PATH}/conf/iotdb-common.properties
}
start_iotdb() { # 启动iotdb
	cd ${TEST_DATANODE_PATH}
	conf_start=$(./sbin/start-confignode.sh >/dev/null 2>&1 &)
	sleep 10
	data_start=$(./sbin/start-datanode.sh >/dev/null 2>&1 &)
	cd ~/
}
start_monitor() { # 启动iotdb-monitor
	cd ${MONITOR_PATH}
	#配置benchmark参数
	sed -i "s/^TEST_DATA_STORE_IP=.*$/TEST_DATA_STORE_IP=${MYSQLHOSTNAME}/g" ${MONITOR_PATH}/conf/config.properties
	sed -i "s/^TEST_DATA_STORE_PORT=.*$/TEST_DATA_STORE_PORT=${PORT}/g" ${MONITOR_PATH}/conf/config.properties
	sed -i "s/^TEST_DATA_STORE_DB=.*$/TEST_DATA_STORE_DB=${DBNAME}/g" ${MONITOR_PATH}/conf/config.properties
	sed -i "s/^TEST_DATA_STORE_USER=.*$/TEST_DATA_STORE_USER=${USERNAME}/g" ${MONITOR_PATH}/conf/config.properties
	sed -i "s/^TEST_DATA_STORE_PW=.*$/TEST_DATA_STORE_PW=${PASSWORD}/g" ${MONITOR_PATH}/conf/config.properties
	if [ ! -d "${MONITOR_PATH}/logs" ]; then
		monitor_start=$(${MONITOR_PATH}/ser-benchmark.sh >/dev/null 2>&1 &)
	else
		rm -rf ${MONITOR_PATH}/logs
		monitor_start=$(${MONITOR_PATH}/ser-benchmark.sh >/dev/null 2>&1 &)
	fi
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
	maxNumofOpenFiles=0
	maxNumofThread=0
	while true; do
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

		csvOutput=${BM_PATH}/data/csvOutput
		if [ ! -d "$csvOutput" ]; then
			now_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
			t_time=$(($(date +%s -d "${now_time}") - $(date +%s -d "${start_time}")))
			if [ $t_time -ge 7200 ]; then
				echo "测试失败"
				mkdir -p ${BM_PATH}/data/csvOutput
				cd ${BM_PATH}/data/csvOutput
				touch Stuck_result.csv
				array1="INGESTION ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1"
				for ((i=0;i<100;i++))
				do
					echo $array1 >> Stuck_result.csv
				done
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
collect_monitor_data() { # 收集iotdb数据大小，顺、乱序文件数量
	dataFileSize=$(du -h -d0 ${TEST_DATANODE_PATH}/data | awk {'print $1'} | awk '{sub(/.$/,"")}1')
	UNIT=$(du -h -d0 ${TEST_DATANODE_PATH}/data | awk {'print $1'} | awk -F '' '$0=$NF')
	if [ "$UNIT" = "M" ]; then
		dataFileSize=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize'/'1024'}'`
	elif [ "$UNIT" = "K" ]; then
		dataFileSize=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize'/'1048576'}'`
	elif [ "$UNIT" = "T" ]; then
        dataFileSize=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize'*'1024'}'`
	else
		dataFileSize=${dataFileSize}
	fi
	numOfSe0Level=$(find ${TEST_DATANODE_PATH}/data/datanode/data/sequence -name "*.tsfile" | wc -l)
	if [ ! -d "${TEST_DATANODE_PATH}/data/datanode/data/unsequence" ]; then
		numOfUnse0Level=0
	else
		numOfUnse0Level=$(find ${TEST_DATANODE_PATH}/data/datanode/data/unsequence -name "*.tsfile" | wc -l)
	fi
	D_ErrorLogSize=$(du -sh ${TEST_DATANODE_PATH}/logs/log_datanode_error.log | awk {'print $1'})
	C_ErrorLogSize=$(du -sh ${TEST_DATANODE_PATH}/logs/log_confignode_error.log | awk {'print $1'})
	if [ "${D_ErrorLogSize}" = "0" ] && [ "${C_ErrorLogSize}" = "0" ]; then
			ErrorLogSize=0
	else
			ErrorLogSize=1
	fi
}
backup_test_data() { # 备份测试数据
	mkdir -p ${BUCKUP_PATH}/$1/${test_date_time}_${commit_id}
	mv ${TEST_IOTDB_PATH} ${BUCKUP_PATH}/$1/${test_date_time}_${commit_id}
	cp -rf ${BM_PATH}/data/csvOutput ${BUCKUP_PATH}/$1/${test_date_time}_${commit_id}
}
clear_expired_file() { # 清理超过七天的文件
	find $1 -mtime +7 -type d -name "*" -exec rm -rf {} \;
}
test_operation() {
	protocol_class=$1
	#写入测试
	for (( i = 0; i < ${#insert_list[*]}; i++ ))
		do
		echo "开始${insert_list[${i}]}写入！"
		ts_type=${insert_list[${i}]}
		#清理环境，确保无就程序影响
		check_monitor_pid
		check_iotdb_pid
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
		#启动iotdb和monitor监控
		start_iotdb
		#start_monitor
		data1=$(date +%Y_%m_%d_%H%M%S | cut -c 1-10)	
		sleep 10
			
		####判断IoTDB是否正常启动
		iotdb_state=$(${TEST_DATANODE_PATH}/sbin/start-cli.sh -e "show version" | grep 'Total line number = 1')
		if [ "${iotdb_state}" = "Total line number = 1" ]; then
			echo "IoTDB正常启动，准备开始测试"
		else
			echo "IoTDB未能正常启动，写入负值测试结果！"
			cost_time=-3
			ts_type='seq_w'
			insert_sql="insert into ${TABLENAME} (test_date_time,commit_id,ts_type,cost_time) values(${test_date_time},'${commit_id}','${ts_type}',${cost_time})"
			mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
			return
		fi
		
		#启动写入程序
		mv_config_file ${insert_list[${i}]}
		start_time=`date -d today +"%Y-%m-%d %H:%M:%S"`
		m_start_time=$(date +%s)
		start_benchmark
		#等待1分钟
		sleep 10
		monitor_test_status
		m_end_time=$(date +%s)
		#停止IoTDB程序和监控程序
		pid=$(${TEST_DATANODE_PATH}/sbin/start-cli.sh -h 127.0.0.1 -p 6667 -u root -pw root -e "flush")
		check_monitor_pid
		check_iotdb_pid

		#收集启动后基础监控数据
		collect_monitor_data
		#测试结果收集写入数据库
		csvOutputfile=${BM_PATH}/data/csvOutput/*result.csv
		read okOperation okPoint failOperation failPoint throughput <<<$(cat ${csvOutputfile} | grep ^INGESTION | sed -n '1,1p' | awk -F, '{print $2,$3,$4,$5,$6}')
		read Latency MIN P10 P25 MEDIAN P75 P90 P95 P99 P999 MAX <<<$(cat ${csvOutputfile} | grep ^INGESTION | sed -n '2,2p' | awk -F, '{print $2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12}')

		cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
		insert_sql="insert into ${TABLENAME} (test_date_time,commit_id,ts_type,okPoint,okOperation,failPoint,failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,errorLogSize,remark) values(${test_date_time},'${commit_id}','${ts_type}',${okPoint},${okOperation},${failPoint},${failOperation},${throughput},${Latency},${MIN},${P10},${P25},${MEDIAN},${P75},${P90},${P95},${P99},${P999},${MAX},${numOfSe0Level},'${start_time}','${end_time}',${cost_time},${numOfUnse0Level},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${errorLogSize},'${protocol_class}')"
		echo ${commit_id}版本${ts_type}写入${okPoint}数据点平均耗时${Latency}秒。吞吐率为：${throughput} 点/秒
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
		
	done
}
mv_config_file() { # 移动配置文件
	rm -rf ${BM_PATH}/conf/config.properties
	cp -rf ${INIT_PATH}/conf/$1 ${BM_PATH}/conf/config.properties
}
#启动后无限循环执行-之后加入crontab之后可以去掉该层循环
for (( comp_test = 1; comp_test <= 3;))
do
# 获取git commit对比判定是否启动测试
cd ${IOTDB_PATH}
last_cid=$(git log --pretty=format:"%h" -1)
#last_cid=0
#更新iotdb代码
git_pull=$(timeout 100s git fetch --all)
#git_pull=$(git reset --hard origin/master)
git_pull=$(timeout 100s git pull)
#git reset --hard 048ceca
# 获取更新后git commit对比判定是否启动测试
commit_id=$(git log --pretty=format:"%h" -1)
#对比判定是否启动测试
if [ "${last_cid}" = "${commit_id}" ]; then
	echo "无代码更新，当前版本${commit_id}已经执行过测试"
	sleep 300s
	#continue
else
	echo "当前版本${commit_id}未执行过测试，即将编译后启动"
	init_items
	test_date_time=`date +%Y%m%d%H%M%S`
	#代码编译
	comp_mvn=$(timeout 6000s mvn clean package -pl distribution -am -DskipTests)
	if [ $? -eq 0 ]
	then
		echo "编译完成，准备开始测试！"
	else
		echo "编译失败，写入负值测试结果！"
		cost_time=-1
		ts_type='common'
		insert_sql="insert into ${TABLENAME} (test_date_time,commit_id,ts_type,cost_time,remark) values(${test_date_time},'${commit_id}','${ts_type}',${cost_time},'111')"
		#mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
		sleep 600
		continue
	fi
	###############################测试开始###############################
	echo "开始测试！"
	test_operation 223 
	test_operation 111
	###############################测试完成###############################
	echo "本轮测试${test_date_time}已结束."
fi
done
