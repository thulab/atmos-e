#!/bin/sh
#登录用户名
ACCOUNT=atmos
#初始环境存放路径
INIT_PATH=/home/atmos/zk_test
IOTDB_PATH=${INIT_PATH}/timechodb
FILENAME=${INIT_PATH}/gitlog.txt
REPO_PATH=/nasdata/repository/master
REPO_PATH_BK=/newnasdata/repository/master
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
author=0
se_insert=0
unse_insert=0
se_query=0
unse_query=0
commpaction=0
sql_coverage=0
api_insert=0
weeklytest_insert=0
weeklytest_query=0
routine_test=0
config_insert=0
remark=0
}
sendEmail() {
	error_type=$1
	date_time=`date +%Y%m%d%H%M%S`
	mailto='qingxin.feng@hotmail.com'
	test_type=${HOSTNAME}
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
			mailbody='错误类型：'${test_type}'代码编译失败<BR>报错时间：'${date_time}'<BR>报错Commit：'${commit_id}'<BR>提交人：'${author}''
			msgbody='错误类型：'${test_type}'代码编译失败\n报错时间：'${date_time}'\n报错Commit：'${commit_id}'\n<BR>提交人：'${author}''
			;;
		#*)
		#exit -1
		#;;
	esac
	curl 'https://oapi.dingtalk.com/robot/send?access_token=f2d691d45da9a0307af8bbd853e90d0785dbaa3a3b0219dd2816882e19859e62' -H 'Content-Type: application/json' -d '{"msgtype": "text","text": {"content": "[Atmos]'${msgbody}'"}}' > /dev/null 2>&1 &
}
#启动后无限循环执行-之后加入crontab之后可以去掉该层循环
for (( comp_test = 1; comp_test <= 3;))
do
	# 获取git commit对比判定是否启动测试
	cd ${IOTDB_PATH}
	git_pull=$(timeout 100s git fetch --all)
	git_pull=$(timeout 100s git reset --hard origin/master)
	git_pull=$(timeout 100s git pull)
	commit_id_list=(`git log --pretty=format:"%h" -11 | awk -F "|" '{print $1}' | cut -c1-7`)
	for (( i = 10; i >= 0; i--))
	do
		query_sql="select commit_id from ${TABLENAME} where commit_id='${commit_id_list[$i]}'"
		echo "$query_sql"
		abc=$(mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${query_sql}" | sed -n '2p')
		if [ "${abc}" = "" ]; then
			cd ${IOTDB_PATH}
			git_pull=$(timeout 100s git fetch --all)
			git_pull=$(timeout 100s git reset --hard origin/master)
			git_pull=$(timeout 100s git pull)
			git_reset=$(timeout 100s git reset --hard ${commit_id_list[$i]})
			# 获取更新后git commit对比判定是否启动测试
			commit_id=$(git log --pretty=format:"%h" -1 | cut -c1-7)
			author=$(git log --pretty=format:"%an" -1)
			#commit_id=${commit_id_list[$i]}
			commit_date_time=$(git log --pretty=format:"%ai" -1 | cut -b 1-19 | sed s/-//g | sed s/://g | sed s/[[:space:]]//g)
			#对比判定是否启动测试
			echo "当前版本${commit_id}未记录,即将编译。"
			#代码编译
			comp_mvn=$(mvn clean package -pl distribution -am -DskipTests)
			if [ $? -eq 0 ]
			then
				echo "编译完成！"
				test_date_time=`date +%Y%m%d%H%M%S`
				mkdir -p ${REPO_PATH}/${commit_id}/apache-iotdb/
				echo $commit_date_time
				echo $test_date_time
				cp -rf ${IOTDB_PATH}/distribution/target/timechodb-*-bin/timechodb-*-bin/* ${REPO_PATH}/${commit_id}/apache-iotdb/
				#配置文件整理
				#rm -rf ${REPO_PATH}/${commit_id}/apache-iotdb/conf/iotdb-system.properties
				#mv ${REPO_PATH}/${commit_id}/apache-iotdb/conf/iotdb-system.properties.template ${REPO_PATH}/${commit_id}/apache-iotdb/conf/iotdb-system.properties
				#向新的网盘环境复制一份备份
				mkdir -p ${REPO_PATH_BK}/${commit_id}/apache-iotdb/
				cp -rf ${IOTDB_PATH}/distribution/target/timechodb-*-bin/timechodb-*-bin/* ${REPO_PATH_BK}/${commit_id}/apache-iotdb/
				#配置文件整理
				#rm -rf ${REPO_PATH_BK}/${commit_id}/apache-iotdb/conf/iotdb-system.properties
				#mv ${REPO_PATH_BK}/${commit_id}/apache-iotdb/conf/iotdb-system.properties.template ${REPO_PATH_BK}/${commit_id}/apache-iotdb/conf/iotdb-system.properties
				#获取本次更新的变更文件列表
				git log -1 --name-only > $FILENAME
				#按照文件夹名称排除不必要测试文件夹
				for (( ix = 0; ix < ${#filter_list_folder_name[*]}; ix++ ))
				do
					sed -i "/${filter_list_folder_name[${ix}]}/d" $FILENAME
				done
				file_num=0
				non_file_num=0
				while read line;do
					filename=$(basename $line)
					if echo "$filename" | grep -q -E '\.java$'
					then
						file_num=$[${file_num}+1]
					else
						non_file_num=$[${non_file_num}+1]
					fi
				done <  $FILENAME
				if [ "${file_num}" = "0" ]; then
					#不需要测试
					str_noneed='NoNeed'
					insert_sql="insert into ${TABLENAME} (commit_date_time,commit_id,author,se_insert,unse_insert,se_query,unse_query,compaction,sql_coverage,weeklytest_insert,weeklytest_query,api_insert,routine_test,config_insert,ts_performance,cluster_insert,cluster_insert_2,cluster_insert_dt,benchants,pipe_test,windows_test,helishi_test) values(${commit_date_time},'${commit_id}','${author}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}','${str_noneed}')"
					mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
				else
					#正常下派所有任务
					insert_sql="insert into ${TABLENAME} (commit_date_time,commit_id,author) values(${commit_date_time},'${commit_id}','${author}')"
					mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
					echo "${commit_id}测试任务已发布！"
				fi
			else
				echo "编译失败！"
				str_err='CError'
				insert_sql="insert into ${TABLENAME} (commit_date_time,commit_id,author,se_insert,unse_insert,se_query,unse_query,compaction,sql_coverage,weeklytest_insert,weeklytest_query,api_insert,routine_test,config_insert,ts_performance,cluster_insert,cluster_insert_2,cluster_insert_dt,benchants,pipe_test,windows_test,helishi_test) values(${commit_date_time},'${commit_id}','${author}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}','${str_err}')"
                mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"
				sendEmail 2
			fi
		else
			echo "当前${commit_id_list[$i]}已经存在！"
		fi
	done
	echo "当前查询到的10个commitid都已经存在！"
	echo "别闲着，做一轮服务器空间清理任务吧。删除15天之前的测试记录"
	find /nasdata/repository/*/*/ -mtime +15 -type d -name "*" -exec rm -rf {} \;
	sleep 300s
done


