#!/usr/bin/env bash
#登录用户名
ACCOUNT=root
test_type=longrun_7_24
IOTDB_PASSWORD="TimechoDB@2021"

#初始环境存放路径
INIT_PATH=/root/zk_test
ATMOS_PATH=${INIT_PATH}/atmos-e
BM_PATH=${INIT_PATH}/iot-benchmark
BUCKUP_PATH=/nasdata/repository/longrun_7_24
REPOS_PATH=/nasdata/repository/master
#测试数据运行路径
TEST_PATH=/data/atmos/zk_test/first-rest-test
TEST_DATANODE_PATH=${TEST_PATH}/DN/apache-iotdb
TEST_CONFIGNODE_PATH=${TEST_PATH}/CN/apache-iotdb
BM_PATH_TREE=${TEST_PATH}/iot-benchmark-tree
BM_PATH_TABLE=${TEST_PATH}/iot-benchmark-table
# 1. org.apache.iotdb.consensus.simple.SimpleConsensus
# 2. org.apache.iotdb.consensus.ratis.RatisConsensus
# 3. org.apache.iotdb.consensus.iot.IoTConsensus
protocol_class=(0 org.apache.iotdb.consensus.simple.SimpleConsensus org.apache.iotdb.consensus.ratis.RatisConsensus org.apache.iotdb.consensus.iot.IoTConsensus)
protocol_list=(111 223)
query_type_csv=(PRECISE_POINT TIME_RANGE VALUE_RANGE AGG_RANGE AGG_VALUE AGG_RANGE_VALUE GROUP_BY LATEST_POINT RANGE_QUERY_DESC VALUE_RANGE_QUERY_DESC GROUP_BY_DESC)
query_type_name=(PRECISE_POINT TIME_RANGE VALUE_RANGE AGG_RANGE AGG_VALUE AGG_RANGE_VALUE GROUP_BY LATEST_POINT RANGE_QUERY_DESC VALUE_RANGE_QUERY_DESC GROUP_BY_DESC)
IP_list=(0 11.101.10.2 11.101.10.3 11.101.10.4 11.101.10.5)
D_IP_list=(0 11.101.10.2 11.101.10.3 11.101.10.4)
C_IP_list=(0 11.101.10.2 11.101.10.3 11.101.10.4)
B_IP_list=(0 11.101.10.5)
config_schema_replication_factor=(0 3 3 3 3 3 3)
config_data_replication_factor=(0 3 3 3 3 3 3)
config_node_config_nodes=(0 11.101.10.2:10710 11.101.10.2:10710 11.101.10.2:10710)
data_node_config_nodes=(0 11.101.10.2:10710 11.101.10.3:10710 11.101.10.4:10710)
Control=172.20.70.51

############mysql信息##########################
MYSQLHOSTNAME="111.200.37.158" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD=${ATMOS_DB_PASSWORD}
DBNAME="QA_ATM"  #数据库名称
TABLENAME="test_result_longrun_test" #数据库中表的名称
TASK_TABLENAME="commit_history" #数据库中任务表的名称
############prometheus##########################
metric_server="111.200.37.158:19090"
############公用函数##########################
if [ "${PASSWORD}" = "" ]; then
	echo "ATMOS_DB_PASSWORD 未设置，停止执行。" >&2
	exit 1
fi
BENCHMARK_RESULT_COMMON="${ATMOS_PATH}/script/common/benchmark_result_common.sh"
if [ ! -f "${BENCHMARK_RESULT_COMMON}" ]; then
	echo "缺少 Benchmark 结果解析脚本: ${BENCHMARK_RESULT_COMMON}" >&2
	exit 1
fi
# shellcheck source=script/common/benchmark_result_common.sh
source "${BENCHMARK_RESULT_COMMON}" || exit 1
cleanup_test_type_file() {
	echo "${test_type}" > "${INIT_PATH}/test_type_file"
}
trap cleanup_test_type_file EXIT
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
	local iotdb_source="${REPOS_PATH}/${commit_id}/apache-iotdb"
	[ -d "${iotdb_source}" ] || return 1
	[ -d "${BM_PATH}" ] || return 1
	rm -rf "${TEST_PATH}" || return 1
	mkdir -p "${TEST_PATH}/CN/apache-iotdb" "${TEST_PATH}/DN/apache-iotdb" "${BM_PATH_TREE}" "${BM_PATH_TABLE}" || return 1
	cp -rf "${iotdb_source}/." "${TEST_PATH}/CN/apache-iotdb/" || return 1
	mkdir -p "${TEST_PATH}/CN/apache-iotdb/activation" || return 1
	cp -rf "${iotdb_source}/." "${TEST_PATH}/DN/apache-iotdb/" || return 1
	cp -rf "${BM_PATH}/." "${BM_PATH_TREE}/" || return 1
	cp -rf "${BM_PATH}/." "${BM_PATH_TABLE}/" || return 1
	rm -rf "${BM_PATH_TREE}/data" "${BM_PATH_TREE}/logs" || return 1
	rm -rf "${BM_PATH_TABLE}/data" "${BM_PATH_TABLE}/logs" || return 1
}
modify_iotdb_config() { # iotdb调整内存，关闭合并
	#修改IoTDB的配置
	[ -f "${TEST_DATANODE_PATH}/conf/datanode-env.sh" ] || return 1
	[ -f "${TEST_CONFIGNODE_PATH}/conf/confignode-env.sh" ] || return 1
	[ -f "${TEST_DATANODE_PATH}/conf/iotdb-system.properties" ] || return 1
	[ -f "${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties" ] || return 1
	sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"192G\"/g" "${TEST_DATANODE_PATH}/conf/datanode-env.sh" || return 1
	sed -i "s/^#ON_HEAP_MEMORY=\"2G\".*$/ON_HEAP_MEMORY=\"8G\"/g" "${TEST_CONFIGNODE_PATH}/conf/confignode-env.sh" || return 1
	sed -i "s/^#OFF_HEAP_MEMORY=\"2G\".*$/OFF_HEAP_MEMORY=\"16G\"/g" "${TEST_DATANODE_PATH}/conf/datanode-env.sh" || return 1
	sed -i "s/^#OFF_HEAP_MEMORY=\"2G\".*$/OFF_HEAP_MEMORY=\"2G\"/g" "${TEST_CONFIGNODE_PATH}/conf/confignode-env.sh" || return 1
	#清空配置文件
	# echo "只保留要修改的参数" > ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	#关闭影响写入性能的其他功能
	#echo "enable_seq_space_compaction=false" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	#echo "enable_unseq_space_compaction=false" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	#echo "enable_cross_space_compaction=false" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	#修改集群名称
	echo "cluster_name=LongRunTestCluster" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "cluster_name=LongRunTestCluster" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
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
	

	echo "schema_region_group_extension_policy=CUSTOM" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "default_schema_region_group_num_per_database=10" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "data_region_group_extension_policy=CUSTOM" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "default_data_region_group_num_per_database=10" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties
	echo "disk_space_warning_threshold=0.01" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties	
	echo "enable_auto_repair_compaction=false" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties	

	echo "schema_region_group_extension_policy=CUSTOM" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "default_schema_region_group_num_per_database=10" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "data_region_group_extension_policy=CUSTOM" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "default_data_region_group_num_per_database=10" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties
	echo "disk_space_warning_threshold=0.01" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties	
	echo "enable_auto_repair_compaction=false" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties

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
OPTIND=1
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
  return 1
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
	ssh ${ACCOUNT}@${IP_list[${i}]} "sudo reboot"
done
sleep 300
for (( i = 1; i < ${#IP_list[*]}; i++ ))
do
	echo "setting env to ${IP_list[${i}]} ..."
	#删除原有路径下所有
	ssh ${ACCOUNT}@${IP_list[${i}]} "rm -rf ${TEST_PATH} && mkdir -p ${TEST_PATH}" || return 1
	#复制license（好像也不需要这样）
	[ -f "${ATMOS_PATH}/conf/${test_type}/license/${IP_list[${i}]}" ] || return 1
	[ -f "${ATMOS_PATH}/conf/${test_type}/env/${IP_list[${i}]}" ] || return 1
	rm -rf "${TEST_PATH}/CN/apache-iotdb/activation/license" "${TEST_PATH}/CN/apache-iotdb/.env" || return 1
	cp -f "${ATMOS_PATH}/conf/${test_type}/license/${IP_list[${i}]}" "${TEST_PATH}/CN/apache-iotdb/activation/license" || return 1
	cp -f "${ATMOS_PATH}/conf/${test_type}/env/${IP_list[${i}]}" "${TEST_PATH}/CN/apache-iotdb/.env" || return 1
	#复制三项到客户机
	scp -r "${TEST_PATH}/." "${ACCOUNT}@${IP_list[${i}]}:${TEST_PATH}/" || return 1
done
echo "开始部署ConfigNode！"
for (( i = 1; i <= $config_num; i++ ))
do
	#修改IoTDB ConfigNode的配置
	ssh ${ACCOUNT}@${C_IP_list[${i}]} "cat >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties <<'EOF'
cn_internal_address=${C_IP_list[${i}]}
cn_seed_config_node=${config_node_config_nodes[${i}]}
schema_replication_factor=${config_schema_replication_factor[${i}]}
data_replication_factor=${config_data_replication_factor[${i}]}
EOF" || return 1
done
echo "开始部署DataNode！"
for (( i = 1; i <= $data_num; i++ ))
do
	#修改IoTDB DataNode的配置
	ssh ${ACCOUNT}@${D_IP_list[${i}]} "cat >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties <<'EOF'
dn_rpc_address=${D_IP_list[${i}]}
dn_internal_address=${D_IP_list[${i}]}
dn_seed_config_node=${dcn_str}
EOF" || return 1
done
#启动config_num个IoTDB ConfigNode节点
	for (( j = 1; j <= $config_num; j++ ))
	do
		echo "starting IoTDB ConfigNode on ${C_IP_list[${j}]} ..."
		ssh ${ACCOUNT}@${C_IP_list[${j}]} "${TEST_CONFIGNODE_PATH}/sbin/start-confignode.sh -H ${TEST_CONFIGNODE_PATH}/cn_dump.hprof > /dev/null 2>&1 &" || return 1
	#主节点需要先启动，所以等待10秒是为了保证主节点启动完毕
	sleep 10
done
#启动data_num个IoTDB DataNode节点
	for (( j = 1; j <= $data_num; j++ ))
	do
		echo "starting IoTDB DataNode on ${D_IP_list[${j}]} ..."
		ssh ${ACCOUNT}@${D_IP_list[${j}]} "${TEST_DATANODE_PATH}/sbin/start-datanode.sh -H ${TEST_DATANODE_PATH}/dn_dump.hprof > /dev/null 2>&1 &" || return 1
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
if [ "$check_config_num" != "$config_num" ] || [ "$check_data_num" != "$data_num" ]; then
	echo "IoTDB 节点启动数量不符合预期：ConfigNode ${check_config_num}/${config_num}，DataNode ${check_data_num}/${data_num}" >&2
	return 1
fi
for (( j = 1; j <= $data_num; j++ ))
do
	flag=0
	for (( t_wait = 0; t_wait <= 20; t_wait++ ))
	do
	  str1=$(ssh ${ACCOUNT}@${D_IP_list[${j}]} "${TEST_DATANODE_PATH}/sbin/start-cli.sh -h ${D_IP_list[${j}]} -p 6667 -e \"show cluster\" | grep 'Total line number = ${total_nodes}'")
	  if [ "$str1" = "Total line number = ${total_nodes}" ]; then
		echo "All Nodes is ready"
		flag=1
		break
	  else
		echo "All Nodes is not ready.Please wait ..."
		sleep 3
		continue
	  fi
	done
	if [ "$flag" != "1" ]; then
	  echo "All Nodes is not ready!"
	  return 1
	fi
done
echo "All ${check_config_num} ConfigNodes and ${check_data_num} DataNodes have been started"
ssh ${ACCOUNT}@${D_IP_list[1]} "${TEST_DATANODE_PATH}/sbin/start-cli.sh -h ${D_IP_list[1]} -p 6667 -e \"ALTER USER root SET PASSWORD '${IOTDB_PASSWORD}'\"" >/dev/null || return 1
ssh ${ACCOUNT}@${D_IP_list[1]} "${TEST_DATANODE_PATH}/sbin/start-cli.sh -h ${D_IP_list[1]} -p 6667 -u root -pw ${IOTDB_PASSWORD} -e \"CREATE USER qa_user 'test123456789';\"" >/dev/null || return 1
ssh ${ACCOUNT}@${D_IP_list[1]} "${TEST_DATANODE_PATH}/sbin/start-cli.sh -h ${D_IP_list[1]} -p 6667 -u root -pw ${IOTDB_PASSWORD} -e \"GRANT ALL ON root.** TO USER qa_user WITH GRANT OPTION;\"" >/dev/null || return 1
ssh ${ACCOUNT}@${D_IP_list[1]} "${TEST_DATANODE_PATH}/sbin/start-cli.sh -h ${D_IP_list[1]} -p 6667 -u root -pw ${IOTDB_PASSWORD} -sql_dialect table -e \"GRANT ALL TO USER qa_user;\"" >/dev/null || return 1

#启动benchmark
sleep 60
if [ "$bm_num" != '' ]; then
	for ((j = 1; j <= $bm_num; j++)); do
		ssh ${ACCOUNT}@${B_IP_list[${j}]} "cd ${BM_PATH_TREE} && nohup ./benchmark.sh > /dev/null 2>&1 < /dev/null &" || return 1
		ssh ${ACCOUNT}@${B_IP_list[${j}]} "cd ${BM_PATH_TABLE} && nohup ./benchmark.sh > /dev/null 2>&1 < /dev/null &" || return 1
	done
	echo "All BMs have been started"
fi
}
remote_result_exists() {
	local benchmark_path=$1
	ssh ${ACCOUNT}@${B_IP_list[1]} "find '${benchmark_path}/data/csvOutput' -maxdepth 1 -type f -name '*result.csv' -print -quit 2>/dev/null | grep -q ."
}
create_remote_stuck_result() {
	local benchmark_path=$1
	local csv_path="${benchmark_path}/data/csvOutput/Stuck_result.csv"
	local array1="INGESTION ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1"
	ssh ${ACCOUNT}@${B_IP_list[1]} "mkdir -p '${benchmark_path}/data/csvOutput' && : > '${csv_path}' && i=0; while [ \$i -lt 100 ]; do printf '%s\n' '${array1}' >> '${csv_path}'; i=\$((i + 1)); done"
}
monitor_test_status() { # 监控两组 benchmark，必须都生成结果文件才算成功
	local process_count=0
	local now_epoch=0
	local elapsed=0
	local tree_ready=0
	local table_ready=0
	while true; do
		if ! process_count=$(ssh ${ACCOUNT}@${B_IP_list[1]} "jps | awk '\$2 == \"App\" {count++} END {print count + 0}'" 2>/dev/null); then
			echo "无法查询 benchmark 进程状态" >&2
			return 1
		fi
		if ! [[ "${process_count}" =~ ^[0-9]+$ ]]; then
			echo "benchmark 进程数量无效: ${process_count}" >&2
			return 1
		fi
		if [ "${process_count}" -eq 0 ]; then
			tree_ready=0
			table_ready=0
			remote_result_exists "${BM_PATH_TREE}" && tree_ready=1
			remote_result_exists "${BM_PATH_TABLE}" && table_ready=1
			if [ "${tree_ready}" -eq 1 ] && [ "${table_ready}" -eq 1 ]; then
				end_time=$(date -d today +"%Y-%m-%d %H:%M:%S")
				cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
				echo "tree 和 table benchmark 均已完成并生成结果"
				return 0
			fi
			echo "benchmark 进程已结束，但 tree/table 结果文件不完整" >&2
			return 1
		fi

		now_epoch=$(date +%s)
		elapsed=$((now_epoch - m_start_time))
		if [ "${elapsed}" -ge 864000 ]; then
			echo "测试超时，生成兜底结果" >&2
			end_time=-1
			cost_time=-1
			create_remote_stuck_result "${BM_PATH_TREE}" || true
			create_remote_stuck_result "${BM_PATH_TABLE}" || true
			return 1
		fi
		sleep 60
	done
}
function get_single_index() {
    # 获取 prometheus 单个指标的值
	local query=$1
    local end=$2
    local url="http://${metric_server}/api/v1/query"
	local index_value=""
	index_value=$(curl -G -s "${url}" \
		--data-urlencode "query=${query}" \
		--data-urlencode "time=${end}" \
		| jq -r '.data.result[0].value[1] // 0') || index_value=0
	if [[ "$index_value" == "null" || -z "$index_value" ]]; then 
		index_value=0
	fi
	echo "${index_value}"
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
	maxCPULoad=$(get_single_index "max_over_time(sys_cpu_load{instance=~\"${D_IP_list[${TEST_IP}]}:9091\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	avgCPULoad=$(get_single_index "avg_over_time(sys_cpu_load{instance=~\"${D_IP_list[${TEST_IP}]}:9091\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOOpsRead=$(get_single_index "rate(disk_io_ops{instance=~\"${D_IP_list[${TEST_IP}]}:9091\",disk_id=~\"sdb\",type=~\"read\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOOpsWrite=$(get_single_index "rate(disk_io_ops{instance=~\"${D_IP_list[${TEST_IP}]}:9091\",disk_id=~\"sdb\",type=~\"write\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOSizeRead=$(get_single_index "rate(disk_io_size{instance=~\"${D_IP_list[${TEST_IP}]}:9091\",disk_id=~\"sdb\",type=~\"read\"}[$((m_end_time-m_start_time))s])" $m_end_time)
	maxDiskIOSizeWrite=$(get_single_index "rate(disk_io_size{instance=~\"${D_IP_list[${TEST_IP}]}:9091\",disk_id=~\"sdb\",type=~\"write\"}[$((m_end_time-m_start_time))s])" $m_end_time)
}
mv_config_file() { # 移动配置文件
	[ -f "${ATMOS_PATH}/conf/${test_type}/benchmark/aligned" ] || return 1
	[ -f "${ATMOS_PATH}/conf/${test_type}/benchmark/tablemode" ] || return 1
	rm -f "${BM_PATH_TREE}/conf/config.properties" || return 1
	cp -f "${ATMOS_PATH}/conf/${test_type}/benchmark/aligned" "${BM_PATH_TREE}/conf/config.properties" || return 1
	rm -f "${BM_PATH_TABLE}/conf/config.properties" || return 1
	cp -f "${ATMOS_PATH}/conf/${test_type}/benchmark/tablemode" "${BM_PATH_TABLE}/conf/config.properties" || return 1
}
fetch_remote_result_csv() {
	local benchmark_path=$1
	local result_dir="${BM_PATH}/TestResult/csvOutput"
	local remote_output=""
	local remote_file=""
	local remote_files=()
	local local_result_file=""

	remote_output=$(ssh ${ACCOUNT}@${B_IP_list[1]} "find '${benchmark_path}/data/csvOutput' -maxdepth 1 -type f -name '*result.csv' -print 2>/dev/null | sort") || return 1
	while IFS= read -r remote_file; do
		[ -n "${remote_file}" ] && remote_files+=("${remote_file}")
	done <<< "${remote_output}"
	if [ "${#remote_files[@]}" -ne 1 ]; then
		echo "${benchmark_path} 预期 1 个结果文件，实际 ${#remote_files[@]} 个" >&2
		return 1
	fi

	mkdir -p "${result_dir}" || return 1
	rm -f "${result_dir}"/*
	scp "${ACCOUNT}@${B_IP_list[1]}:${remote_files[0]}" "${result_dir}/" >/dev/null || return 1
	local_result_file="${result_dir}/${remote_files[0]##*/}"
	[ -s "${local_result_file}" ] || return 1
	printf '%s\n' "${local_result_file}"
}
query_is_enabled() {
	local config_file=$1
	local query_index=$2
	local ratio=""
	ratio=$(awk -F= -v field_index=$((query_index + 2)) '
		$1 == "OPERATION_PROPORTION" {
			split($2, values, ":")
			print values[field_index]
			exit
		}
	' "${config_file}")
	[[ "${ratio}" =~ ^[0-9]+$ ]] && [ "${ratio}" -gt 0 ]
}
move_remote_dump_if_exists() {
	local host=$1
	local source_path=$2
	local target_path=$3
	ssh ${ACCOUNT}@${host} "if [ -f '${source_path}' ]; then sudo mv '${source_path}' '${target_path}'; fi"
}
test_operation() {
	ts_type=$1
	data_type=$2
	protocol_class=$3
	echo "开始测试！"
	#复制当前程序到执行位置
	set_env || return 1
	modify_iotdb_config || return 1
	if [ "${protocol_class}" = "111" ]; then
		set_protocol_class 1 1 1 || return 1
	elif [ "${protocol_class}" = "222" ]; then
		set_protocol_class 2 2 2 || return 1
	elif [ "${protocol_class}" = "223" ]; then
		set_protocol_class 2 2 3 || return 1
    elif [ "${protocol_class}" = "211" ]; then
        set_protocol_class 2 1 1 || return 1
	else
		echo "协议设置错误！"
		return 1
	fi
	mv_config_file || return 1
	setup_nCmD -c3 -d3 -t1 || return 1
	echo "测试开始！"
	start_time=`date -d today +"%Y-%m-%d %H:%M:%S"`
	m_start_time=$(date +%s)
	#等待1分钟
	sleep 60
	monitor_test_status || return 1
	m_end_time=$(date +%s)
	#测试结果收集写入数据库
	ts_type="table"
	data_type="seq_rw"
	csvOutputfile=$(fetch_remote_result_csv "${BM_PATH_TABLE}") || return 1
	parse_benchmark_csv_operation_result "${csvOutputfile}" "INGESTION" || {
		echo "table Benchmark 缺少有效的 INGESTION 结果" >&2
		return 1
	}
	for ((j = 1; j <= 3; j++)); do
		#收集启动后基础监控数据
		collect_monitor_data ${j}
		op_type="INGESTION"
		#cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
		node_id=${j}
		insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,node_id,ts_type,data_type,op_type,okPoint,okOperation,failPoint,failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,walFileSize,avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,remark,protocol) values(${commit_date_time},${test_date_time},'${commit_id}','${author}',${node_id},'${ts_type}','${data_type}','${op_type}',${okPoint},${okOperation},${failPoint},${failOperation},${throughput},${Latency},${MIN},${P10},${P25},${MEDIAN},${P75},${P90},${P95},${P99},${P999},${MAX},${numOfSe0Level},'${start_time}','${end_time}',${cost_time},${numOfUnse0Level},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${walFileSize},${avgCPULoad},${maxCPULoad},${maxDiskIOSizeRead},${maxDiskIOSizeWrite},${maxDiskIOOpsRead},${maxDiskIOOpsWrite},'${data_type}','${protocol_class}')"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}" || return 1
		
		sudo mkdir -p ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/${j}/CN || return 1
		sudo mkdir -p ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/${j}/DN || return 1
		ssh ${ACCOUNT}@${C_IP_list[${j}]} "sudo cp -rf ${TEST_CONFIGNODE_PATH}/logs ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/${j}/CN" || return 1
		ssh ${ACCOUNT}@${D_IP_list[${j}]} "sudo cp -rf ${TEST_DATANODE_PATH}/logs ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/${j}/DN" || return 1
		move_remote_dump_if_exists "${D_IP_list[${j}]}" "${TEST_DATANODE_PATH}/dn_dump.hprof" "${INIT_PATH}/${commit_date_time}_${commit_id}_${protocol_class}_node${j}_dn_dump.hprof" || return 1
		move_remote_dump_if_exists "${C_IP_list[${j}]}" "${TEST_CONFIGNODE_PATH}/cn_dump.hprof" "${INIT_PATH}/${commit_date_time}_${commit_id}_${protocol_class}_node${j}_cn_dump.hprof" || return 1
	done	
	
	for (( i = 0; i < ${#query_type_csv[*]}; i++ ))
	do
		query_is_enabled "${BM_PATH_TABLE}/conf/config.properties" "${i}" || continue
		op_type="${query_type_name[${i}]}"
		parse_benchmark_csv_operation_result "${csvOutputfile}" "${query_type_csv[${i}]}" || {
			echo "table Benchmark 缺少有效的 ${query_type_csv[${i}]} 结果" >&2
			return 1
		}
		node_id=1
		insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,node_id,ts_type,data_type,op_type,okPoint,okOperation,failPoint,failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,walFileSize,avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,remark,protocol) values(${commit_date_time},${test_date_time},'${commit_id}','${author}',${node_id},'${ts_type}','${data_type}','${op_type}',${okPoint},${okOperation},${failPoint},${failOperation},${throughput},${Latency},${MIN},${P10},${P25},${MEDIAN},${P75},${P90},${P95},${P99},${P999},${MAX},${numOfSe0Level},'${start_time}','${end_time}',${cost_time},${numOfUnse0Level},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${walFileSize},${avgCPULoad},${maxCPULoad},${maxDiskIOSizeRead},${maxDiskIOSizeWrite},${maxDiskIOOpsRead},${maxDiskIOOpsWrite},'${data_type}','${protocol_class}')"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}" || return 1
	done
	sudo cp -f "${csvOutputfile}" ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/table.csv || return 1
	
	
	#测试结果收集写入数据库
	ts_type="tree"
	data_type="seq_rw"
	csvOutputfile=$(fetch_remote_result_csv "${BM_PATH_TREE}") || return 1
	parse_benchmark_csv_operation_result "${csvOutputfile}" "INGESTION" || {
		echo "tree Benchmark 缺少有效的 INGESTION 结果" >&2
		return 1
	}
	for ((j = 1; j <= 3; j++)); do
		#收集启动后基础监控数据
		collect_monitor_data ${j}
		op_type="INGESTION"
		#cost_time=$(($(date +%s -d "${end_time}") - $(date +%s -d "${start_time}")))
		node_id=${j}
		insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,node_id,ts_type,data_type,op_type,okPoint,okOperation,failPoint,failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,walFileSize,avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,remark,protocol) values(${commit_date_time},${test_date_time},'${commit_id}','${author}',${node_id},'${ts_type}','${data_type}','${op_type}',${okPoint},${okOperation},${failPoint},${failOperation},${throughput},${Latency},${MIN},${P10},${P25},${MEDIAN},${P75},${P90},${P95},${P99},${P999},${MAX},${numOfSe0Level},'${start_time}','${end_time}',${cost_time},${numOfUnse0Level},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${walFileSize},${avgCPULoad},${maxCPULoad},${maxDiskIOSizeRead},${maxDiskIOSizeWrite},${maxDiskIOOpsRead},${maxDiskIOOpsWrite},'${data_type}','${protocol_class}')"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}" || return 1
		
		sudo mkdir -p ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/${j}/CN || return 1
		sudo mkdir -p ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/${j}/DN || return 1
		ssh ${ACCOUNT}@${C_IP_list[${j}]} "sudo cp -rf ${TEST_CONFIGNODE_PATH}/logs ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/${j}/CN" || return 1
		ssh ${ACCOUNT}@${D_IP_list[${j}]} "sudo cp -rf ${TEST_DATANODE_PATH}/logs ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/${j}/DN" || return 1
		move_remote_dump_if_exists "${D_IP_list[${j}]}" "${TEST_DATANODE_PATH}/dn_dump.hprof" "${INIT_PATH}/${commit_date_time}_${commit_id}_${protocol_class}_node${j}_dn_dump.hprof" || return 1
		move_remote_dump_if_exists "${C_IP_list[${j}]}" "${TEST_CONFIGNODE_PATH}/cn_dump.hprof" "${INIT_PATH}/${commit_date_time}_${commit_id}_${protocol_class}_node${j}_cn_dump.hprof" || return 1
	done	
	
	for (( i = 0; i < ${#query_type_csv[*]}; i++ ))
	do
		query_is_enabled "${BM_PATH_TREE}/conf/config.properties" "${i}" || continue
		op_type="${query_type_name[${i}]}"
		parse_benchmark_csv_operation_result "${csvOutputfile}" "${query_type_csv[${i}]}" || {
			echo "tree Benchmark 缺少有效的 ${query_type_csv[${i}]} 结果" >&2
			return 1
		}
		node_id=1
		insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,node_id,ts_type,data_type,op_type,okPoint,okOperation,failPoint,failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,walFileSize,avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,remark,protocol) values(${commit_date_time},${test_date_time},'${commit_id}','${author}',${node_id},'${ts_type}','${data_type}','${op_type}',${okPoint},${okOperation},${failPoint},${failOperation},${throughput},${Latency},${MIN},${P10},${P25},${MEDIAN},${P75},${P90},${P95},${P99},${P999},${MAX},${numOfSe0Level},'${start_time}','${end_time}',${cost_time},${numOfUnse0Level},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${walFileSize},${avgCPULoad},${maxCPULoad},${maxDiskIOSizeRead},${maxDiskIOSizeWrite},${maxDiskIOOpsRead},${maxDiskIOOpsWrite},'${data_type}','${protocol_class}')"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}" || return 1
	done
	sudo cp -f "${csvOutputfile}" ${BUCKUP_PATH}/${commit_date_time}_${commit_id}_${protocol_class}/tree.csv || return 1
	return 0
}

##准备开始测试
echo "ontesting" > ${INIT_PATH}/test_type_file
query_sql="SELECT commit_id,',',author,',',commit_date_time,',' FROM ${TASK_TABLENAME} WHERE ${test_type} = 'retest' ORDER BY commit_date_time desc limit 1 "
result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${query_sql}") || exit 1
commit_id=$(echo $result_string| awk -F, '{print $4}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
author=$(echo $result_string| awk -F, '{print $5}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
commit_date_time=$(echo $result_string | awk -F, '{print $6}' | sed s/-//g | sed s/://g | sed s/[[:space:]]//g | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
##查询是否有复测任务
if [ "${commit_id}" = "" ]; then
	query_sql="SELECT commit_id,',',author,',',commit_date_time,',' FROM ${TASK_TABLENAME} WHERE ${test_type} is NULL ORDER BY commit_date_time desc limit 1 "
	result_string=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${query_sql}") || exit 1
	commit_id=$(echo $result_string| awk -F, '{print $4}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
	author=$(echo $result_string| awk -F, '{print $5}' | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
	commit_date_time=$(echo $result_string | awk -F, '{print $6}' | sed s/-//g | sed s/://g | sed s/[[:space:]]//g | awk '{sub(/^ */, "");sub(/ *$/, "")}1')
fi
if [ "${commit_id}" = "" ]; then
	sleep 60s
else
	update_sql="update ${TASK_TABLENAME} set ${test_type} = 'ontesting' where commit_id = '${commit_id}'"
	mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}" || exit 1
	echo "当前版本${commit_id}未执行过测试，即将编译后启动"
	init_items
	test_date_time=`date +%Y%m%d%H%M%S`
	########优先测试
	echo "开始测试普通时间序列顺序写入！"
	test_operation both seq_rw 223
	echo "本轮测试${test_date_time}已结束."
	update_sql="update ${TASK_TABLENAME} set ${test_type} = 'done' where commit_id = '${commit_id}'"
	mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql}" || exit 1
	update_sql02="update ${TASK_TABLENAME} set ${test_type} = 'skip' where ${test_type} is NULL and commit_date_time < '${commit_date_time}'"
	mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${update_sql02}" || exit 1
fi
echo "${test_type}" > ${INIT_PATH}/test_type_file
