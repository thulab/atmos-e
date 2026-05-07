#!/bin/sh
#登录用户名
ACCOUNT=root
IoTDB_PW=TimechoDB@2021
test_type=cluster_insert_2
#初始环境存放路径
INIT_PATH=/root/zk_test
ATMOS_PATH=${INIT_PATH}/atmos-e
BM_PATH=${INIT_PATH}/iot-benchmark
BUCKUP_PATH=/nasdata/repository/cluster_insert_2
REPOS_PATH=/nasdata/repository/master
#测试数据运行路径
TEST_PATH=/data/cluster/first-rest-test
TEST_DATANODE_PATH=${TEST_PATH}/DN/apache-iotdb
TEST_CONFIGNODE_PATH=${TEST_PATH}/CN/apache-iotdb
# 1. org.apache.iotdb.consensus.simple.SimpleConsensus
# 2. org.apache.iotdb.consensus.ratis.RatisConsensus
# 3. org.apache.iotdb.consensus.iot.IoTConsensus
# 4. org.apache.iotdb.consensus.iot.IoTConsensusV2
protocol_class=(0 org.apache.iotdb.consensus.simple.SimpleConsensus org.apache.iotdb.consensus.ratis.RatisConsensus org.apache.iotdb.consensus.iot.IoTConsensus org.apache.iotdb.consensus.iot.IoTConsensusV2)
protocol_list=(111 223 222 224)
ts_list=(common aligned template tempaligned)

IP_list=(0 172.20.70.22 172.20.70.23 172.20.70.24 172.20.70.7 172.20.70.8 172.20.70.9)
D_IP_list=(0 172.20.70.22 172.20.70.23 172.20.70.24 172.20.70.7 172.20.70.8)
C_IP_list=(0 172.20.70.22 172.20.70.23 172.20.70.24 172.20.70.7 172.20.70.8)
B_IP_list=(0 172.20.70.9)
config_schema_replication_factor=(0 3 3 3 3 3 3)
config_data_replication_factor=(0 3 3 3 3 3 3)
config_node_config_nodes=(0 172.20.70.22:10710 172.20.70.22:10710 172.20.70.22:10710)
data_node_config_nodes=(0 172.20.70.22:10710 172.20.70.23:10710 172.20.70.24:10710)
Control=172.20.70.20

############mysql信息##########################
MYSQLHOSTNAME="111.200.37.158" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD=${ATMOS_DB_PASSWORD}
DBNAME="QA_ATM"  #数据库名称
TABLENAME="test_result_cluster_insert_2" #数据库中表的名称
TASK_TABLENAME="commit_history" #数据库中任务表的名称
############prometheus##########################
metric_server="172.20.70.11:9090"
############公用函数##########################
if [ "${PASSWORD}" = "" ]; then
echo "需要关注密码设置！"
fi
#echo "Started at: " date -d today +"%Y-%m-%d %H:%M:%S"
echo "检查iot-benchmark版本"
BM_REPOS_PATH=/nasdata/repository/iot-benchmark
BM_NEW=$(cat ${BM_REPOS_PATH}/git.properties | grep git.commit.id.abbrev | awk -F= '{print $2}')
BM_OLD=$(cat ${BM_PATH}/git.properties | grep git.commit.id.abbrev | awk -F= '{print $2}')
if [ "${BM_OLD}" != "cat: git.properties: No such file or directory" ] && [ "${BM_OLD}" != "${BM_NEW}" ]; then
	rm -rf ${BM_PATH}
	cp -rf ${BM_REPOS_PATH} ${BM_PATH}
fi
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
	if [ ! -d "${TEST_PATH}" ]; then
		mkdir -p ${TEST_PATH}
		mkdir -p ${TEST_PATH}/CN/apache-iotdb
		mkdir -p ${TEST_PATH}/DN/apache-iotdb
	else
		rm -rf ${TEST_PATH}
		mkdir -p ${TEST_PATH}
		mkdir -p ${TEST_PATH}/CN/apache-iotdb
		mkdir -p ${TEST_PATH}/DN/apache-iotdb
	fi
	
	cp -rf ${REPOS_PATH}/${commit_id}/apache-iotdb/* ${TEST_PATH}/CN/apache-iotdb/
	mkdir -p ${TEST_PATH}/CN/apache-iotdb/activation
	cp -rf ${ATMOS_PATH}/conf/${test_type}/license ${TEST_PATH}/CN/apache-iotdb/activation/
	cp -rf ${ATMOS_PATH}/conf/${test_type}/env ${TEST_PATH}/CN/apache-iotdb/.env
	
	cp -rf ${REPOS_PATH}/${commit_id}/apache-iotdb/* ${TEST_PATH}/DN/apache-iotdb/
}
modify_iotdb_config() { # iotdb调整内存，关闭合并
	#修改IoTDB的配置
	sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"20G\"/g" ${TEST_DATANODE_PATH}/conf/datanode-env.sh
	sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"6G\"/g" ${TEST_CONFIGNODE_PATH}/conf/confignode-env.sh
	#清空配置文件
	# echo "只保留要修改的参数" > ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	#关闭影响写入性能的其他功能
	echo "enable_seq_space_compaction=false" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "enable_unseq_space_compaction=false" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "enable_cross_space_compaction=false" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	#修改集群名称
	echo "cluster_name=IoTDB-Enterprise-20" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "cluster_name=IoTDB-Enterprise-20" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	#添加启动监控功能
	echo "cn_enable_metric=true" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "cn_enable_performance_stat=true" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "cn_metric_reporter_list=PROMETHEUS" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "cn_metric_level=ALL" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "cn_metric_prometheus_reporter_port=9081" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	#添加启动监控功能
	echo "dn_enable_metric=true" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "dn_enable_performance_stat=true" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "dn_metric_reporter_list=PROMETHEUS" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "dn_metric_level=ALL" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "dn_metric_prometheus_reporter_port=9091" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
}
set_protocol_class() { 
	config_node=$1
	schema_region=$2
	data_region=$3
	#设置协议
	echo "config_node_consensus_protocol_class=${protocol_class[${config_node}]}" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "schema_region_consensus_protocol_class=${protocol_class[${schema_region}]}" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "data_region_consensus_protocol_class=${protocol_class[${data_region}]}" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	#设置协议
	echo "config_node_consensus_protocol_class=${protocol_class[${config_node}]}" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "schema_region_consensus_protocol_class=${protocol_class[${schema_region}]}" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "data_region_consensus_protocol_class=${protocol_class[${data_region}]}" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
}
setup_nCmD() {
while getopts 'c:d:t:' OPT; do
    case $OPT in
        c) config_num="$OPTARG";;
        d) data_num="$OPTARG";;
		t) bm_num="$OPTARG";;
        ?) echo "ERROR";;
    esac
done
###检查参数
if [[ "$config_num" == '' ]] || [[ "$data_num" == '' ]] 
then
  echo "Enter the number of ConfigNodes and datanodes to start."
  exit -1
fi
#拼接config_node参数
dcn_str=''
for (( j = 1; j <= ${config_num}; j++ ))
do
	if [ "$dcn_str" == '' ]; then
		dcn_str=${data_node_config_nodes[${j}]}
	else
		dcn_str=${dcn_str},${data_node_config_nodes[${j}]}
	fi
done
echo "开始重置环境！"
for (( i = 1; i < ${#IP_list[*]}; i++ ))
do
	#ssh ${ACCOUNT}@${IP_list[${i}]} "killall -u ${ACCOUNT} > /dev/null 2>&1 &"
	#ssh ${ACCOUNT}@${IP_list[${i}]} "sudo init 6"
	#ssh ${ACCOUNT}@${IP_list[${i}]} "ps -ef | grep java | grep -v grep | grep '^root' | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1 &"
	#ssh ${ACCOUNT}@${IP_list[${i}]} "sudo sync"
	#ssh ${ACCOUNT}@${IP_list[${i}]} "sudo echo 3 > /proc/sys/vm/drop_caches"
	ssh ${ACCOUNT}@${IP_list[${i}]} "sudo reboot"
done
sleep 180
for (( i = 1; i < ${#IP_list[*]}; i++ ))
do
	echo "setting env to ${IP_list[${i}]} ..."
	#删除原有路径下所有
	ssh ${ACCOUNT}@${IP_list[${i}]} "rm -rf ${TEST_PATH}"
	ssh ${ACCOUNT}@${IP_list[${i}]} "mkdir -p ${TEST_PATH}"
	#复制三项到客户机
	scp -r ${TEST_PATH}/* ${ACCOUNT}@${IP_list[${i}]}:${TEST_PATH}/
done
for ((j = 1; j <= $bm_num; j++)); do
	ssh ${ACCOUNT}@${B_IP_list[${j}]} "rm -rf ${BM_PATH}/logs"
	ssh ${ACCOUNT}@${B_IP_list[${j}]} "rm -rf ${BM_PATH}/data"
done
echo "开始部署ConfigNode！"
for (( i = 1; i <= $config_num; i++ ))
do
	#修改IoTDB ConfigNode的配置
	ssh ${ACCOUNT}@${C_IP_list[${i}]} "echo \"cn_internal_address=${C_IP_list[${i}]}\" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"
	ssh ${ACCOUNT}@${C_IP_list[${i}]} "echo \"cn_seed_config_node=${config_node_config_nodes[${i}]}\" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"
	ssh ${ACCOUNT}@${C_IP_list[${i}]} "echo \"schema_replication_factor=${config_schema_replication_factor[${i}]}\" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"
	ssh ${ACCOUNT}@${C_IP_list[${i}]} "echo \"data_replication_factor=${config_data_replication_factor[${i}]}\" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"	
done
echo "开始部署DataNode！"
for (( i = 1; i <= $data_num; i++ ))
do
	#修改IoTDB DataNode的配置
	ssh ${ACCOUNT}@${D_IP_list[${i}]} "echo \"dn_rpc_address=${D_IP_list[${i}]}\" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties"
	ssh ${ACCOUNT}@${D_IP_list[${i}]} "echo \"dn_internal_address=${D_IP_list[${i}]}\" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties"
	ssh ${ACCOUNT}@${D_IP_list[${i}]} "echo \"dn_seed_config_node=${dcn_str}\" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties"
done
#启动config_num个IoTDB ConfigNode节点
for (( j = 1; j <= $config_num; j++ ))
do
	echo "starting IoTDB ConfigNode on ${C_IP_list[${j}]} ..."
	pid3=$(ssh ${ACCOUNT}@${C_IP_list[${j}]} "${TEST_CONFIGNODE_PATH}/sbin/start-confignode.sh > /dev/null 2>&1 &")
	#主节点需要先启动，所以等待10秒是为了保证主节点启动完毕
	sleep 10
done
#启动data_num个IoTDB DataNode节点
for (( j = 1; j <= $data_num; j++ ))
do
	echo "starting IoTDB DataNode on ${D_IP_list[${j}]} ..."
	pid3=$(ssh ${ACCOUNT}@${D_IP_list[${j}]} "${TEST_DATANODE_PATH}/sbin/start-datanode.sh -H ${TEST_DATANODE_PATH}/dn_dump.hprof  > /dev/null 2>&1 &")
done
#等待60s，让服务器完成前期准备
sleep 60
#检查IoTDB ConfigNode节点
check_config_num=0
for (( j = 1; j <= $config_num; j++ ))
do
	for (( t_wait = 0; t_wait <= 3; t_wait++ ))
	do
	  str1=$(ssh ${ACCOUNT}@${C_IP_list[${j}]} "jps | grep -w ConfigNode | grep -v grep | wc -l")
	  if [ "$str1" = "1" ]; then
		echo "ConfigNode has been started on PC:${C_IP_list[${j}]}"
		check_config_num=$[${check_config_num}+1]
		break
	  else
		echo "ConfigNode has not been started on PC:${C_IP_list[${j}]}"
		sleep 30
		continue
	  fi
	done
done
#检查IoTDB DataNode节点
check_data_num=0
for (( j = 1; j <= $data_num; j++ ))
do
	for (( t_wait = 0; t_wait <= 3; t_wait++ ))
	do
	  str1=$(ssh ${ACCOUNT}@${D_IP_list[${j}]} "jps | grep -w DataNode | grep -v grep | wc -l")
	  if [ "$str1" = "1" ]; then
		echo "DataNode has been started on PC:${D_IP_list[${j}]}"
		check_data_num=$[${check_data_num}+1]
		break
	  else
		echo "DataNode has not been started on PC:${D_IP_list[${j}]}"
		sleep 30
		continue
	  fi
	done
done
#检查iotdb DataNode是否可连接节点
total_nodes=$(($config_num+$data_num))
for (( j = 1; j <= $data_num; j++ ))
do
	for (( t_wait = 0; t_wait <= 20; t_wait++ ))
	do
	  str1=$(ssh ${ACCOUNT}@${D_IP_list[${j}]} "${TEST_DATANODE_PATH}/sbin/start-cli.sh -h ${D_IP_list[${j}]} -p 6667 -e \"show cluster\" | grep 'Total line number = ${total_nodes}'")
	  if [ "$str1" = "Total line number = 8" ]; then
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

if [ "$check_config_num" == "$config_num" ] && [ "$check_data_num" == "$data_num" ]; then
	echo "All ${check_config_num} ConfigNodes and ${check_data_num} DataNodes have been started"
	#启动benchmark
	sleep 60
	if [ "$bm_num" != '' ];
	then
		for ((j = 1; j <= $bm_num; j++)); do
			ssh ${ACCOUNT}@${B_IP_list[${j}]} "rm -rf ${BM_PATH}"
			scp -r ${BM_PATH} ${ACCOUNT}@${B_IP_list[${j}]}:${BM_PATH}
			ssh ${ACCOUNT}@${B_IP_list[${j}]} "rm -rf ${BM_PATH}/conf/config.properties"
			scp -r ${BM_PATH}/conf/config.properties ${ACCOUNT}@${B_IP_list[${j}]}:${BM_PATH}/conf/config.properties
			#echo "启动BM： ${B_IP_list[${j}]} ..."
			ssh ${ACCOUNT}@${B_IP_list[${j}]} "cd ${BM_PATH};${BM_PATH}/benchmark.sh > /dev/null 2>&1 &" &
		done
		wait
		echo "All BMs have been started"
	fi	
fi
}
monitor_test_status() { # 监控测试运行状态，获取最大打开文件数量和最大线程数
	while true; do
		flag=0
		for (( j = 1; j <= 1; j++ ))
		do
			str1=$(ssh ${ACCOUNT}@${B_IP_list[${j}]} "jps | grep -w App | grep -v grep | wc -l" 2>/dev/null)
			if [ "$str1" = "1" ]; then
				echo "测试未结束:${B_IP_list[${j}]}"  > /dev/null 2>&1 &
			else
				echo "测试已结束:${B_IP_list[${j}]}"
				flag=$[${flag}+1]
			fi
		done
		now_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
		t_time=$(($(date +%s -d "${now_time}") - $(date +%s -d "${start_time}")))
		if [ $t_time -ge 30000 ]; then
			echo "测试失败"
			end_time=-1
			cost_time=-1
			ssh ${ACCOUNT}@${B_IP_list[1]} "mkdir -p ${BM_PATH}/data/csvOutput"
			ssh ${ACCOUNT}@${B_IP_list[1]} "touch ${BM_PATH}/data/Stuck_result.csv"
			array1="INGESTION ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1"
			for ((i=0;i<100;i++))
			do
				ssh ${ACCOUNT}@${B_IP_list[1]} "echo $array1 >> ${BM_PATH}/data/Stuck_result.csv"
			done
			break
		fi
		if [ "$flag" = "1" ]; then
			end_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
			cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
			# 获取 DataNode 文件句柄
			for (( i = 1; i <= $data_num; i++ )); do
				ip=${D_IP_list[${i}]}
				ssh ${ACCOUNT}@${ip} "mkdir -p ${TEST_DATANODE_PATH}/logs"
				ssh ${ACCOUNT}@${ip} "
PID=\$(pgrep -x DataNode | head -1)
if [ -n \"\$PID\" ] && [ -d \"/proc/\$PID\" ]; then
	PROC_CMD=\$(ps -o comm= -p \$PID 2>/dev/null || echo 'DataNode')
	PROC_CMDLINE=\$(tr '\\0' ' ' < \"/proc/\$PID/cmdline\" 2>/dev/null || echo 'unknown')
	PROC_USER=\$(ps -o user= -p \$PID 2>/dev/null || echo 'unknown')
	TIMESTAMP=\$(date '+%Y-%m-%d %H:%M:%S')
	COUNT=0
	{
		echo '=========================================='
		echo ' 进程文件句柄报告'
		echo \" 进程名称: \$PROC_CMD\"
		echo \" 完整命令: \$PROC_CMDLINE\"
		echo \" 用户: \$PROC_USER\"
		echo \" PID: \$PID\"
		echo \" 时间: \$TIMESTAMP\"
		echo '=========================================='
		echo ''
		printf '%-6s  %-10s  %-8s  %s\\n' 'FD' '类型' '权限' '路径'
		printf '%-6s  %-10s  %-8s  %s\\n' '------' '----------' '--------' '----'
		for fd_path in \"/proc/\$PID/fd\"/*; do
			[[ -e \"\$fd_path\" ]] || continue
			fd_num=\$(basename \"\$fd_path\")
			target=\$(readlink \"\$fd_path\" 2>/dev/null || echo '(无法读取)')
			if [[ \"\$target\" == pipe:* ]]; then
				fd_type='管道'
			elif [[ \"\$target\" == socket:* ]]; then
				fd_type='套接字'
			elif [[ \"\$target\" == anon_inode:* ]]; then
				fd_type='匿名inode'
			elif [[ \"\$target\" == /dev/* ]]; then
				fd_type='设备'
			else
				fd_type='文件'
			fi
			flags=\$(cat \"/proc/\$PID/fdinfo/\$fd_num\" 2>/dev/null | grep '^flags:' | awk '{print \$2}')
			if [[ -n \"\$flags\" ]]; then
				access_mode=\$((8#\$flags & 3))
				case \$access_mode in
					0) perm='只读' ;;
					1) perm='只写' ;;
					2) perm='读写' ;;
					*) perm='未知' ;;
				esac
			else
				perm='-'
			fi
			printf '%-6s  %-10s  %-8s  %s\\n' \"\$fd_num\" \"\$fd_type\" \"\$perm\" \"\$target\"
			((COUNT++))
		done
		echo ''
		echo '=========================================='
		echo \" 总计: \$COUNT 个句柄\"
		echo '=========================================='
		soft=\$(cat \"/proc/\$PID/limits\" 2>/dev/null | grep 'Max open files' | awk '{print \$4}')
		hard=\$(cat \"/proc/\$PID/limits\" 2>/dev/null | grep 'Max open files' | awk '{print \$5}')
		if [[ -n \"\$soft\" ]]; then
			echo ''
			echo '--- 文件描述符限制 ---'
			echo \"软限制: \$soft\"
			echo \"硬限制: \$hard\"
			echo \"已使用: \$COUNT / \$soft (\$((COUNT*100/soft))%)\"
		fi
	} > \"${TEST_DATANODE_PATH}/logs/handles_DataNode.txt\"
	echo \"Found \$COUNT handles for DataNode on \$ip\"
else
	echo \"DataNode not found on \$ip\"
fi
"
			done
			# 获取 ConfigNode 文件句柄
			for (( i = 1; i <= $config_num; i++ )); do
				ip=${C_IP_list[${i}]}
				ssh ${ACCOUNT}@${ip} "mkdir -p ${TEST_CONFIGNODE_PATH}/logs"
				ssh ${ACCOUNT}@${ip} "
PID=\$(pgrep -x ConfigNode | head -1)
if [ -n \"\$PID\" ] && [ -d \"/proc/\$PID\" ]; then
	PROC_CMD=\$(ps -o comm= -p \$PID 2>/dev/null || echo 'ConfigNode')
	PROC_CMDLINE=\$(tr '\\0' ' ' < \"/proc/\$PID/cmdline\" 2>/dev/null || echo 'unknown')
	PROC_USER=\$(ps -o user= -p \$PID 2>/dev/null || echo 'unknown')
	TIMESTAMP=\$(date '+%Y-%m-%d %H:%M:%S')
	COUNT=0
	{
		echo '=========================================='
		echo ' 进程文件句柄报告'
		echo \" 进程名称: \$PROC_CMD\"
		echo \" 完整命令: \$PROC_CMDLINE\"
		echo \" 用户: \$PROC_USER\"
		echo \" PID: \$PID\"
		echo \" 时间: \$TIMESTAMP\"
		echo '=========================================='
		echo ''
		printf '%-6s  %-10s  %-8s  %s\\n' 'FD' '类型' '权限' '路径'
		printf '%-6s  %-10s  %-8s  %s\\n' '------' '----------' '--------' '----'
		for fd_path in \"/proc/\$PID/fd\"/*; do
			[[ -e \"\$fd_path\" ]] || continue
			fd_num=\$(basename \"\$fd_path\")
			target=\$(readlink \"\$fd_path\" 2>/dev/null || echo '(无法读取)')
			if [[ \"\$target\" == pipe:* ]]; then
				fd_type='管道'
			elif [[ \"\$target\" == socket:* ]]; then
				fd_type='套接字'
			elif [[ \"\$target\" == anon_inode:* ]]; then
				fd_type='匿名inode'
			elif [[ \"\$target\" == /dev/* ]]; then
				fd_type='设备'
			else
				fd_type='文件'
			fi
			flags=\$(cat \"/proc/\$PID/fdinfo/\$fd_num\" 2>/dev/null | grep '^flags:' | awk '{print \$2}')
			if [[ -n \"\$flags\" ]]; then
				access_mode=\$((8#\$flags & 3))
				case \$access_mode in
					0) perm='只读' ;;
					1) perm='只写' ;;
					2) perm='读写' ;;
					*) perm='未知' ;;
				esac
			else
				perm='-'
			fi
			printf '%-6s  %-10s  %-8s  %s\\n' \"\$fd_num\" \"\$fd_type\" \"\$perm\" \"\$target\"
			((COUNT++))
		done
		echo ''
		echo '=========================================='
		echo \" 总计: \$COUNT 个句柄\"
		echo '=========================================='
		soft=\$(cat \"/proc/\$PID/limits\" 2>/dev/null | grep 'Max open files' | awk '{print \$4}')
		hard=\$(cat \"/proc/\$PID/limits\" 2>/dev/null | grep 'Max open files' | awk '{print \$5}')
		if [[ -n \"\$soft\" ]]; then
			echo ''
			echo '--- 文件描述符限制 ---'
			echo \"软限制: \$soft\"
			echo \"硬限制: \$hard\"
			echo \"已使用: \$COUNT / \$soft (\$((COUNT*100/soft))%)\"
		fi
	} > \"${TEST_CONFIGNODE_PATH}/logs/handles_ConfigNode.txt\"
	echo \"Found \$COUNT handles for ConfigNode on \$ip\"
else
	echo \"ConfigNode not found on \$ip\"
fi
"
			done
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
	dataFileSize=$(get_single_index "sum(file_global_size{instance=~\"${D_IP_list[${TEST_IP}]}:9091\"})" $m_end_time)
	dataFileSize=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize'/'1048576'}'`
	dataFileSize=`awk 'BEGIN{printf "%.2f\n",'$dataFileSize'/'1024'}'`
	numOfSe0Level=$(get_single_index "sum(file_global_count{instance=~\"${D_IP_list[${TEST_IP}]}:9091\",name=\"seq\"})" $m_end_time)
	numOfUnse0Level=$(get_single_index "sum(file_global_count{instance=~\"${D_IP_list[${TEST_IP}]}:9091\",name=\"unseq\"})" $m_end_time)
	maxNumofThread_C=$(get_single_index "max_over_time(process_threads_count{instance=~\"${D_IP_list[${TEST_IP}]}:9081\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxNumofThread_D=$(get_single_index "max_over_time(process_threads_count{instance=~\"${D_IP_list[${TEST_IP}]}:9091\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	let maxNumofThread=${maxNumofThread_C}+${maxNumofThread_D}
	maxNumofOpenFiles=$(get_single_index "max_over_time(file_count{instance=~\"${D_IP_list[${TEST_IP}]}:9091\",name=\"open_file_handlers\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	walFileSize=$(get_single_index "max_over_time(file_size{instance=~\"${D_IP_list[${TEST_IP}]}:9091\",name=~\"wal\"}[$((m_end_time-m_start_time))s])" $m_end_time)
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
	sudo rm -rf ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}
	sudo mkdir -p ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}
    sudo rm -rf ${TEST_DATANODE_PATH}/data
	sudo mv ${TEST_DATANODE_PATH} ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}
	sudo cp -rf ${BM_PATH}/data/csvOutput ${BUCKUP_PATH}/$1/${commit_date_time}_${commit_id}_${protocol_class}
}
mv_config_file() { # 移动配置文件
	rm -rf ${BM_PATH}/conf/config.properties
	cp -rf ${ATMOS_PATH}/conf/${test_type}/$1/$2 ${BM_PATH}/conf/config.properties
}
test_operation() {
	ts_type=$1
	data_type=$2
	protocol_class=$3
	echo "开始测试${ts_type}时间序列！"
	#复制当前程序到执行位置
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
    elif [ "${protocol_class}" = "224" ]; then
        set_protocol_class 2 2 4
	else
		echo "协议设置错误！"
		return
	fi
	
	mv_config_file ${ts_type} ${data_type}
	sed -i "s/^HOST=.*$/HOST=${D_IP_list[1]}/g" ${BM_PATH}/conf/config.properties
	setup_nCmD -c3 -d5 -t1
	change_pwd=$(${TEST_DATANODE_PATH}/sbin/start-cli.sh -h ${D_IP_list[1]} -p 6667 -e "ALTER USER root SET PASSWORD '${IoTDB_PW}'")
	echo "测试开始！"
	start_time=`date -d today +"%Y-%m-%d %H:%M:%S"`
	m_start_time=$(date +%s)

	#等待1分钟
	sleep 60
	monitor_test_status
	m_end_time=$(date +%s)
	#测试结果收集写入数据库
	if [ ! -d "${BM_PATH}/TestResult/csvOutput/" ]; then
		mkdir -p ${BM_PATH}/TestResult/csvOutput/
	fi
	rm -rf ${BM_PATH}/TestResult/csvOutput/*
	scp -r ${ACCOUNT}@${B_IP_list[1]}:${BM_PATH}/data/csvOutput/*result.csv ${BM_PATH}/TestResult/csvOutput/
	for ((j = 1; j <= 5; j++)); do
		#收集启动后基础监控数据
		collect_monitor_data ${j}
		csvOutputfile=${BM_PATH}/TestResult/csvOutput/*result.csv
		read okOperation okPoint failOperation failPoint throughput <<<$(cat ${csvOutputfile} | grep ^INGESTION | sed -n '1,1p' | awk -F, '{print $2,$3,$4,$5,$6}')
		read Latency MIN P10 P25 MEDIAN P75 P90 P95 P99 P999 MAX <<<$(cat ${csvOutputfile} | grep ^INGESTION | sed -n '2,2p' | awk -F, '{print $2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12}')
		#cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
		node_id=${j}
		insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,node_id,ts_type,okPoint,okOperation,failPoint,failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,walFileSize,avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,remark,protocol) values(${commit_date_time},${test_date_time},'${commit_id}','${author}',${node_id},'${ts_type}',${okPoint},${okOperation},${failPoint},${failOperation},${throughput},${Latency},${MIN},${P10},${P25},${MEDIAN},${P75},${P90},${P95},${P99},${P999},${MAX},${numOfSe0Level},'${start_time}','${end_time}',${cost_time},${numOfUnse0Level},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${walFileSize},${avgCPULoad},${maxCPULoad},${maxDiskIOSizeRead},${maxDiskIOSizeWrite},${maxDiskIOOpsRead},${maxDiskIOOpsWrite},'${data_type}','${protocol_class}')"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
		
		sudo mkdir -p ${BUCKUP_PATH}/${ts_type}/${commit_date_time}_${commit_id}_${data_type}_${protocol_class}/${j}/CN
		sudo mkdir -p ${BUCKUP_PATH}/${ts_type}/${commit_date_time}_${commit_id}_${data_type}_${protocol_class}/${j}/DN
		scp -r ${ACCOUNT}@${C_IP_list[${j}]}:${TEST_CONFIGNODE_PATH}/logs ${BUCKUP_PATH}/${ts_type}/${commit_date_time}_${commit_id}_${data_type}_${protocol_class}/${j}/CN
		scp -r ${ACCOUNT}@${C_IP_list[${j}]}:${TEST_DATANODE_PATH}/logs ${BUCKUP_PATH}/${ts_type}/${commit_date_time}_${commit_id}_${data_type}_${protocol_class}/${j}/DN
	done
	for (( i = 1; i < ${#IP_list[*]}; i++ ))
	do
		pid3=$(ssh ${ACCOUNT}@${IP_list[${i}]} "${TEST_DATANODE_PATH}/sbin/stop-standalone.sh > /dev/null 2>&1 &")
	done
	sleep 10
	sudo cp -rf ${BM_PATH}/TestResult/csvOutput/* ${BUCKUP_PATH}/${ts_type}/${commit_date_time}_${commit_id}_${data_type}_${protocol_class}/
	sudo scp -r ${ACCOUNT}@${B_IP_list[1]}:${BM_PATH}/logs ${BUCKUP_PATH}/${ts_type}/${commit_date_time}_${commit_id}_${data_type}_${protocol_class}/
}

##准备开始测试
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
	########优先测试
	echo "开始测试普通时间序列顺序写入！"
	test_operation common seq_w 223
	echo "开始测试对齐时间序列顺序写入！"
	test_operation aligned seq_w 223
	test_operation aligned seq_w 222
	test_operation aligned seq_w 224
	echo "开始测试表模型时间序列顺序写入！"
	test_operation tablemode seq_w 223
	###############################普通时间序列###############################
	#echo "开始测试普通时间序列顺序写入！"
	#test_operation common seq_w 223
	echo "开始测试普通时间序列乱序写入！"
	test_operation common unseq_w 223
	#echo "开始测试普通时间序列顺序读写混合！"
	#test_operation common seq_rw 223
	#echo "开始测试普通时间序列乱序读写混合！"
	#test_operation common unseq_rw 223
	###############################对齐时间序列###############################
	#echo "开始测试对齐时间序列顺序写入！"
	#test_operation aligned seq_w 223
	#test_operation aligned seq_w 222
	echo "开始测试对齐时间序列乱序写入！"
	test_operation aligned unseq_w 223
	test_operation aligned unseq_w 222
	test_operation aligned unseq_w 224
	echo "开始测试对齐时间序列顺序读写混合！"
	test_operation aligned seq_rw 223
	echo "开始测试对齐时间序列乱序读写混合！"
	test_operation aligned unseq_rw 223
	###############################模板时间序列###############################
	#echo "开始测试模板时间序列顺序写入！"
	#test_operation template seq_w 223
	#echo "开始测试模板时间序列乱序写入！"
	#test_operation template unseq_w 223
	#echo "开始测试模板时间序列顺序读写混合！"
	#test_operation template seq_rw 223
	#echo "开始测试模板时间序列乱序读写混合！"
	#test_operation template unseq_rw 223
	###############################对齐模板时间序列###############################
	#echo "开始测试对齐模板时间序列顺序写入！"
	#test_operation tempaligned seq_w 223
	#echo "开始测试对齐模板时间序列乱序写入！"
	#test_operation tempaligned unseq_w 223
	#echo "开始测试对齐模板时间序列顺序读写混合！"
	#test_operation tempaligned seq_rw 223
	#echo "开始测试对齐模板时间序列乱序读写混合！"
	#test_operation tempaligned unseq_rw 223	
	###############################表模型时间序列###############################
	#echo "开始测试表模型时间序列顺序写入！"
	#test_operation tablemode seq_w 223
	echo "开始测试表模型时间序列乱序写入！"
	test_operation tablemode unseq_w 223
	echo "开始测试表模型时间序列顺序读写混合！"
	test_operation tablemode seq_rw 223
	echo "开始测试表模型时间序列乱序读写混合！"
	test_operation tablemode unseq_rw 223
	###############################测试完成###############################
	echo "本轮测试${test_date_time}已结束."
	update_sql="update ${TASK_TABLENAME} set ${test_type} = 'done' where commit_id = '${commit_id}'"
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}")
	update_sql02="update ${TASK_TABLENAME} set ${test_type} = 'skip' where ${test_type} is NULL and commit_date_time < '${commit_date_time}'"
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql02}")
fi
echo "${test_type}" > ${INIT_PATH}/test_type_file