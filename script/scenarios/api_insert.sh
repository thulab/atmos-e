#!/usr/bin/env bash
# 场景名称：API 写入测试
# 测试目的：验证不同客户端 API 在指定协议和数据模型下的写入能力，并采集写入性能指标。
# 具体步骤：
# 步骤一：选择待测 IoTDB 版本并同步 benchmark 工具。
# 步骤二：部署 IoTDB，写入测试配置并启动服务。
# 步骤三：按 API 类型启动 benchmark 执行写入压测。
# 步骤四：监控测试过程，解析 benchmark 结果和系统指标。
# 步骤五：将测试结果回写数据库并备份测试现场。
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="172.20.31.39"
readonly TEST_TYPE="api_insert"
readonly -a PROTOCOL_LIST=(223)
readonly -a TS_LIST=(tempaligned)
readonly -a API_LIST=(SESSION_BY_TABLET SESSION_BY_TABLET_TABLE SESSION_BY_RECORDS SESSION_BY_RECORD JDBC)
readonly SCENARIO_ID="api_insert"
readonly TASK_TEST_TYPE="api_insert"
readonly SCENARIO_FAILURE_POLICY="continue_and_fail"
readonly -a SCENARIO_CASE_DIMENSIONS=(
    "protocol=223"
    "case=tempaligned"
    "api=SESSION_BY_TABLET,SESSION_BY_TABLET_TABLE,SESSION_BY_RECORDS,SESSION_BY_RECORD,JDBC"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/../common" && pwd)"
# shellcheck source=script/common/insert_common.sh
source "${COMMON_DIR}/insert_common.sh"
source "${SCRIPT_DIR}/../framework/runner.sh"

run_scenario "$@"
