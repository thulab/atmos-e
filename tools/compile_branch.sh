#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
	exec bash "$0" "$@"
fi
if shopt -oq posix; then
	exec bash "${BASH_SOURCE[0]}" "$@"
fi
#登录用户名
ACCOUNT=atmos
#初始环境存放路径
INIT_PATH=/home/atmos/zk_test
IOTDB_PATH=${INIT_PATH}/timechodb_branch
REPO_PATH=/nasdata/repository/master
REPO_PATH_BK=/newnasdata/repository/master

############mysql信息##########################
MYSQLHOSTNAME="111.200.37.158" #数据库信息
PORT="13306"
USERNAME="iotdbatm"
PASSWORD=${ATMOS_DB_PASSWORD}
DBNAME="QA_ATM"  #数据库名称
TABLENAME="commit_history" #数据库中表的名称
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATMOS_PATH="${ATMOS_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
COMMON_DIR="${ATMOS_PATH}/script/common"
# shellcheck source=script/common/shell_common.sh
source "${COMMON_DIR}/shell_common.sh"
# shellcheck source=script/common/precise_test_common.sh
source "${COMMON_DIR}/precise_test_common.sh"
# shellcheck source=tools/compile_legacy_common.sh
source "${SCRIPT_DIR}/compile_legacy_common.sh"
############公用函数##########################
if [ "${PASSWORD}" = "" ]; then
echo "需要关注密码设置！"
fi
cd ${IOTDB_PATH}
git_pull=$(timeout 100s git fetch --all)
git_pull=$(timeout 100s git reset --hard origin/master)
git_pull=$(timeout 100s git pull)
git_check=$(timeout 100s git checkout $1)
git_pull=$(timeout 100s git pull)
if [ "$1" = "" ]; then
	echo "编译当前分支最新版本"
else
	echo "编译当前分支 $2 版本"
	git_reset=$(timeout 100s git reset --hard $2)
fi
commit_id=$(git log --pretty=format:"%h" -1 | cut -c1-7)
author=$(git log --pretty=format:"%an" -1)
commit_date_time=$(git log --pretty=format:"%ci" -1 | cut -b 1-19 | sed s/-//g | sed s/://g | sed s/[[:space:]]//g)
#对比判定是否启动测试
echo "当前版本${commit_id}即将编译和下派。"
#代码编译
date_time=`date +%Y%m%d%H%M%S`
comp_mvn=$(mvn clean package -pl distribution -am -DskipTests)
if [ $? -eq 0 ]
then
	echo "${commit_id}编译完成！"
	rm -rf ${REPO_PATH}/${commit_id}
	mkdir -p ${REPO_PATH}/${commit_id}/apache-iotdb/
	cp -rf ${IOTDB_PATH}/distribution/target/timechodb-*-bin/timechodb-*-bin/* ${REPO_PATH}/${commit_id}/apache-iotdb/
	#配置文件整理
	#rm -rf ${REPO_PATH}/${commit_id}/apache-iotdb/conf/iotdb-system.properties
	#mv ${REPO_PATH}/${commit_id}/apache-iotdb/conf/iotdb-system.properties.template ${REPO_PATH}/${commit_id}/apache-iotdb/conf/iotdb-system.properties
	#向新的网盘环境复制一份备份
	#rm -rf ${REPO_PATH_BK}/${commit_id}
	#mkdir -p ${REPO_PATH_BK}/${commit_id}/apache-iotdb/
	#cp -rf ${IOTDB_PATH}/distribution/target/iotdb-enterprise-*-bin/iotdb-enterprise-*-bin/* ${REPO_PATH}/${commit_id}/apache-iotdb/

	#正常下派所有任务
	insert_sql="insert into ${TABLENAME} (commit_date_time,commit_id,author,remark) values(${commit_date_time},'${commit_id}','${author}','$1')"
	if mysql -h${MYSQLHOSTNAME} -P${PORT} -u${USERNAME} -p${PASSWORD} ${DBNAME} -e "${insert_sql}"; then
		PRECISE_TEST_REPO_PATH="${IOTDB_PATH}" apply_precise_test_plan "${commit_id}" "${commit_date_time}" "${author}" "$1"
	else
		echo "commit_history insert failed, skip precise test plan for ${commit_id}"
	fi
else
	echo "${commit_id}编译失败！"
	msgbody='错误类型：'$1'分支代码编译失败\n报错时间：'${date_time}'\n报错Commit：'${commit_id}'\n提交人：'${author}''
	sendEmail 2
fi
