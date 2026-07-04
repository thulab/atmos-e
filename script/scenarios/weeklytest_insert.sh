#!/usr/bin/env bash
# 场景名称：周常写入测试
# 测试目的：验证周常 tempaligned/tablemode 写入场景在多协议下的写入性能。
# 具体步骤：
# 步骤一：选择待测 IoTDB 版本并同步 benchmark 工具。
# 步骤二：部署 IoTDB，按周常写入用例加载 benchmark 配置。
# 步骤三：启动 benchmark 执行写入或读写混合测试。
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

readonly TEST_IP="172.20.31.32"
readonly TEST_TYPE="weeklytest_insert"
readonly -a PROTOCOL_LIST=(223 224)
readonly -a INSERT_CASE_LIST=(
    "tempaligned|seq_w|SESSION_BY_TABLET"
    "tempaligned|unseq_w|SESSION_BY_TABLET"
    "tempaligned|seq_rw|SESSION_BY_TABLET"
    "tablemode|seq_w|SESSION_BY_TABLET"
    "tablemode|unseq_w|SESSION_BY_TABLET"
    "tablemode|seq_rw|SESSION_BY_TABLET"
)
readonly -a API_LIST=(SESSION_BY_TABLET)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/../common" && pwd)"
# shellcheck source=script/common/insert_common.sh
source "${COMMON_DIR}/insert_common.sh"

main "$@"
