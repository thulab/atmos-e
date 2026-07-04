#!/usr/bin/env bash
# 场景名称：周常查询测试
# 测试目的：验证周常 sequence/unsequence 数据集在单序列和多序列查询下的性能。
# 具体步骤：
# 步骤一：选择待测 IoTDB 版本并准备周常查询数据集。
# 步骤二：部署 IoTDB，按数据集和传感器规模加载 benchmark 查询配置。
# 步骤三：多轮启动 benchmark 执行查询压测。
# 步骤四：采集查询结果、资源监控指标和错误日志。
# 步骤五：将测试结果回写数据库并备份测试现场。
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="172.20.31.31"
readonly TEST_TYPE="weeklytest_query"
readonly DATA_PATH="/nasdata/weeklytest_query/original"
readonly -a PROTOCOL_LIST=(111)
readonly -a QUERY_DATA_TYPES=(sequence unsequence)
readonly -a QUERY_SENSOR_TYPES=(one more)
readonly IOTDB_PW="TimechoDB@2021"
readonly QUERY_REPEAT_COUNT=2
readonly BENCHMARK_WARMUP_SECONDS=10
readonly -a QUERY_LIST=(
    Q1 Q2-1 Q2-2 Q2-3 Q3-1 Q3-2 Q3-3 Q4a-1 Q4a-2 Q4a-3
    Q4b-1 Q4b-2 Q4b-3 Q5 Q6-1 Q6-2 Q6-3 Q7-1 Q7-2 Q7-3
    Q7-4 Q8 Q9-1 Q9-2 Q9-3 Q10
)
readonly -a QUERY_LABELS=(
    PRECISE_POINT TIME_RANGE TIME_RANGE TIME_RANGE VALUE_RANGE VALUE_RANGE VALUE_RANGE
    AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_VALUE
    AGG_RANGE_VALUE AGG_RANGE_VALUE AGG_RANGE_VALUE GROUP_BY GROUP_BY GROUP_BY
    GROUP_BY LATEST_POINT RANGE_QUERY_DESC RANGE_QUERY_DESC RANGE_QUERY_DESC VALUE_RANGE_QUERY_DESC
)
readonly METRIC_SERVER="172.20.70.11:9090"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/../common" && pwd)"
# shellcheck source=script/common/query_common.sh
source "${COMMON_DIR}/query_common.sh"

IOTDB_READY_USER="root"
IOTDB_READY_PASSWORD="${IOTDB_PW}"

prepare_query_context() {
    local current_suite_type="$1"
    local current_query="$2"
    local current_sensor_type="$3"
    local current_repeat="$4"
    local current_query_label="${5:-}"

    ts_type="common"
    data_type="${current_suite_type}"
    query_type="$(normalize_query_name "${current_query}")"
    query_label_name="${current_query_label}"
    query_suite_type="${current_suite_type}"
    sensor_type="${current_sensor_type}"
    query_num="${current_repeat}"
}

result_extra_columns() {
    printf ',sensor_type,query_num'
}

result_extra_values() {
    printf ',%s,%s' "$(sql_quote "${sensor_type}")" "${query_num}"
}

append_query_specific_iotdb_properties() {
    local properties_file="$1"

    printf 'query_timeout_threshold=6000000\n' >> "${properties_file}"
}

main "$@"
