#!/usr/bin/env bash
# 场景名称：CTS API 写入测试
# 测试目的：验证 CTS 场景下多种客户端 API 的写入兼容性和性能表现。
# 具体步骤：
# 步骤一：选择待测 IoTDB 版本并准备 CTS 写入配置。
# 步骤二：部署 IoTDB，写入协议和 metric 配置后启动服务。
# 步骤三：按 API 类型启动 benchmark 执行 CTS 写入。
# 步骤四：采集 benchmark 结果、监控指标和错误日志。
# 步骤五：将测试结果回写数据库并备份测试现场。
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="172.20.31.29"
readonly TEST_TYPE="api_insert_cts"
readonly -a PROTOCOL_LIST=(223)
readonly -a TS_LIST=(tempaligned)
readonly -a API_LIST=(SESSION_BY_TABLET SESSION_BY_RECORDS SESSION_BY_RECORD JDBC)
readonly ENABLE_BENCHMARK_VERSION_CHECK=0
readonly SCENARIO_ID="api_insert_cts"
readonly TASK_TEST_TYPE="api_insert_cts"
readonly SCENARIO_FAILURE_POLICY="continue_and_fail"
readonly -a SCENARIO_CASE_DIMENSIONS=(
    "protocol=223"
    "case=tempaligned"
    "api=SESSION_BY_TABLET,SESSION_BY_RECORDS,SESSION_BY_RECORD,JDBC"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/../common" && pwd)"
# shellcheck source=script/common/insert_common.sh
source "${COMMON_DIR}/insert_common.sh"
source "${SCRIPT_DIR}/../framework/runner.sh"

run_scenario "$@"
