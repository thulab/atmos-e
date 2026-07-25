#!/usr/bin/env bash
# 场景名称：顺序数据写入测试
# 测试目的：验证顺序时序数据在不同协议、数据模型和写入模式下的写入性能。
# 具体步骤：
# 步骤一：选择待测 IoTDB 版本并同步 benchmark 工具。
# 步骤二：部署 IoTDB，应用顺序写入场景配置并启动服务。
# 步骤三：启动 benchmark 执行顺序数据写入。
# 步骤四：采集写入结果、资源监控指标和日志信息。
# 步骤五：将测试结果回写数据库并备份测试现场。
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="172.20.31.5"
readonly TEST_TYPE="se_insert"

readonly SCENARIO_ID="se_insert"
readonly TASK_TEST_TYPE="se_insert"
readonly SCENARIO_FAILURE_POLICY="continue_and_fail"
readonly -a SCENARIO_CASE_DIMENSIONS=(
    "protocol=223"
    "case=common,aligned,tempaligned,tablemode,tableview"
    "api=SESSION_BY_TABLET"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/../common" && pwd)"
# shellcheck source=script/common/insert_common.sh
source "${COMMON_DIR}/insert_common.sh"
FRAMEWORK_ROOT="$(cd "${SCRIPT_DIR}/../framework" && pwd)"
source "${FRAMEWORK_ROOT}/runner.sh"

run_scenario "$@"
