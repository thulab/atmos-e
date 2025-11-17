#!/bin/sh
#登录用户名
ACCOUNT=root
test_type=compile
#初始环境存放路径
INIT_PATH=/root/zk_test
IOTDB_PATH=${INIT_PATH}/release
FILENAME=${INIT_PATH}/gitlog.txt
REPO_PATH=/nasdata/repository/master
REPO_PATH_EX=/ex_nasdata/repository/master
filter_list_folder_name=(client-cpp client-go client-py code-coverage compile-tools distribution docker docs example external-api external-pipe-api flink-iotdb-connector flink-tsfile-connector grafana-connector grafana-plugin hadoop hive-connector influxdb-protocol integration integration-test isession licenses mlnode openapi pipe-api rewrite-tsfile-tool schema-engine-rocksdb schema-engine-tag site spark-iotdb-connector spark-tsfile subscription-api test testcontainer tools trigger-api udf-api zeppelin-interpreter)

############mysql信息##########################
MYSQLHOSTNAME="111.200.37.158" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD=${ATMOS_DB_PASSWORD}
DBNAME="QA_ATM"  #数据库名称
TABLENAME="commit_history" #数据库中表的名称
############公用函数##########################
if [ "${PASSWORD}" = "" ]; then
echo "需要关注密码设置！"
fi
init_items() {
commit_date_time=0
commit_id=0
commit_headline=0
author=0
se_insert=0
unse_insert=0
se_query=0
unse_query=0
compaction=0
sql_coverage=0
weeklytest_insert=0
weeklytest_query=0
api_insert=0
ts_performance=0
cluster_insert=0
cluster_insert_2=0
insert_records=0
restart_db=0
routine_test=0
config_insert=0
count_ts=0
pipe_test=0
last_cache_query=0
windows_test=0
benchants=0
helishi_test=0
remark=0
}
sendEmail() {
	error_type=$1
	date_time=`date +%Y%m%d%H%M%S`
	mailto='qingxin.feng@hotmail.com'
	#test_type=${HOSTNAME}
	case $error_type in
		1)
		#1.代码更新失败
			headline=''${test_type}'代码更新失败'
			mailbody='错误类型：'${test_type}'代码更新失败<BR>报错时间：'${date_time}''
			msgbody='错误类型：'${test_type}'代码更新失败\n报错时间：'${date_time}''
			;;
		2)
		#2.编译失败
			headline=''${test_type}'代码编译失败'
			mailbody='错误类型：'${test_type}'代码编译失败<BR>报错时间：'${date_time}'<BR>报错Commit：'${commit_id}'<BR>提交人：'${author}'<BR>报错信息：'${comp_mvn}''
			msgbody='错误类型：'${test_type}'代码编译失败\n报错时间：'${date_time}'\n报错Commit：'${commit_id}'\n提交人：'${author}'\n报错信息：'${comp_mvn}''
			;;
		#*)
		#exit -1
		#;;
	esac
	curl 'https://oapi.dingtalk.com/robot/send?access_token=f2d691d45da9a0307af8bbd853e90d0785dbaa3a3b0219dd2816882e19859e62' -H 'Content-Type: application/json' -d '{"msgtype": "text","text": {"content": "[Atmos]'${msgbody}'"}}' > /dev/null 2>&1 &
}

echo "ontesting" > ${INIT_PATH}/test_type_file
init_items
PROCESSED_DIR="/root/zk_test/release/processed"  # 已处理文件存放目录
# 创建必要的目录
mkdir -p "$PROCESSED_DIR"

# 检查文件夹中是否有csv文件
csv_files=("$IOTDB_PATH"/*.csv)
if [ ${#csv_files[@]} -eq 1 ] && [ ! -f "${csv_files[0]}" ]; then
	echo "$(date): 文件夹为空，睡眠10分钟..."
	sleep 600  # 10分钟
else
	# 获取第一个csv文件
	first_csv=$(ls "$IOTDB_PATH"/*.csv 2>/dev/null | head -n1)
	if [ -z "$first_csv" ]; then
		echo "$(date): 没有找到csv文件，睡眠10分钟..."
		sleep 600
	fi
	echo "$(date): 处理文件: $first_csv"

	# 提取文件名（不含路径和扩展名）
	filename=$(basename "$first_csv" .csv)

	# 倒序文件名
	reversed=$(echo "$filename" | rev)

	# 提取第4到第12个字符（倒序后的位置）
	# 注意：字符串索引从1开始，所以是3-11（因为cut从1开始计数）
	commit_id=$(echo "$reversed" | cut -c1-8)

	# 将提取的字符串再次倒序，恢复原始顺序
	commit_id=$(echo "$commit_id" | rev)

	commit_date_time=$(echo "$reversed" | cut -c10-23)
	commit_date_time=$(echo "$commit_date_time" | rev)

	echo "提取的commit_id: $commit_id"
	echo "提取的commit_date_time: $commit_date_time"
	
	read s1 s2 s3 s4 s5<<<$(cat ${csvOutputfile} | sed -n '2,2p' | tr -d '\"' | tr -d "'" | awk -F, '{print $1,$2,$3,$4}')
	author=$s2
	commit_headline=$s5
	query_sql="select commit_id from ${TABLENAME} where commit_id='${commit_id}'"
	echo "$query_sql"
	diff_str=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${query_sql}" | sed -n '2p')
	if [ "${diff_str}" = "" ]; then
		# 寻找包含commit_id的zip文件
		zip_file=$(find "$IOTDB_PATH" -name "*${commit_id}*.zip" | head -n1)

		if [ -n "$zip_file" ]; then
			echo "找到匹配的zip文件: $zip_file"
			echo "正在解压..."
			
			# 解压zip文件到当前文件夹（或指定目录）
			unzip -o "$zip_file" -d "$IOTDB_PATH"
			if [ $? -eq 0 ]; then
				echo "解压成功"
				# 将处理过的zip文件移动到已处理目录
				mv "$zip_file" "$PROCESSED_DIR/"
			else
				echo "解压失败"
			fi
		else
			echo "未找到包含commit_id '$commit_id' 的zip文件"
		fi
		rm -rf ${REPO_PATH}/${commit_id}
		mkdir -p ${REPO_PATH}/${commit_id}/apache-iotdb/
		cp -rf ${IOTDB_PATH}/timechodb-*-SNAPSHOT-bin/* ${REPO_PATH}/${commit_id}/apache-iotdb/
		#配置文件整理
		echo "enforce_strong_password=false" >> ${REPO_PATH}/${commit_id}/apache-iotdb/conf/iotdb-system.properties
		insert_sql="insert into ${TABLENAME} (commit_date_time,commit_id,author,remark) values(${commit_date_time},'${commit_id}','${author}','${commit_headline}')"
		mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
		mv "$first_csv" "$PROCESSED_DIR/"
		mv ${IOTDB_PATH}/timechodb-*-SNAPSHOT-bin "$PROCESSED_DIR/"
	else
		echo "当前${commit_id}已经存在！"
		# 将处理过的csv文件移动到已处理目录
		mv "$first_csv" "$PROCESSED_DIR/"
		mv "$zip_file" "$PROCESSED_DIR/"
	fi
	rm -rf /root/zk_test/release/processed/*
	echo "已完成处理，等待下一轮循环..."
	echo "----------------------------------------"
fi

# 获取当前的星期（1表示星期一，7表示星期天）和小时
day_of_week=$(date +%u)  # 星期几（1-7，1表示星期一）
hour=$(date +%H)         # 当前小时（00-23）
echo $day_of_week
echo $hour
# 判断是否是每周一凌晨1点
if [ "$day_of_week" -eq 1 ] && [ "$hour" -eq 01 ]; then
	echo "It's Monday at 1:00 AM. Running the task..."
	BM_REPOS_PATH=/nasdata/repository/iot-benchmark
	rm -rf ${BM_REPOS_PATH}
	cp -rf ${INIT_PATH}/iot-benchmark ${BM_REPOS_PATH}
fi
echo "别闲着，做一轮服务器空间清理任务吧。删除15天之前的测试记录"
find /nasdata/repository/*/*/ -mtime +15 -type d -name "*" -exec rm -rf {} \;
sleep 300s
echo "${test_type}" > ${INIT_PATH}/test_type_file