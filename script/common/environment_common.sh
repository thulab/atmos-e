#!/usr/bin/env bash

# Stable environment defaults shared by scenario and common scripts.
# A caller may set any value before sourcing this file to override the default.
: "${INIT_PATH:=/root/zk_test}"
: "${ATMOS_PATH:=${INIT_PATH}/atmos-e}"
: "${BM_PATH:=${INIT_PATH}/iot-benchmark}"
: "${REPOS_PATH:=/nasdata/repository/master}"
: "${BM_REPOS_PATH:=/nasdata/repository/iot-benchmark}"
: "${TEST_INIT_PATH:=/data/qa}"
: "${TEST_IOTDB_PATH:=${TEST_INIT_PATH}/apache-iotdb}"

: "${MYSQLHOSTNAME:=111.200.37.158}"
: "${PORT:=13306}"
: "${USERNAME:=iotdbatm}"
: "${PASSWORD:=${ATMOS_DB_PASSWORD:-}}"
: "${DBNAME:=QA_ATM}"
: "${TASK_TABLENAME:=commit_history}"
: "${TASK_DB_PARSE_ERROR_MESSAGE:=commit_date_time parse failed}"
METRIC_SERVER="111.200.37.158:19090"
readonly METRIC_SERVER
