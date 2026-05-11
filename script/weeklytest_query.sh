#!/usr/bin/env bash
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
readonly QUERY_REPEAT_COUNT=2
readonly BENCHMARK_WARMUP_SECONDS=10
readonly -a QUERY_LIST=(
    Q1 Q2-1 Q2-2 Q2-3 Q3-1 Q3-2 Q3-3 Q4-a1 Q4-a2 Q4-a3
    Q4-b1 Q4-b2 Q4-b3 Q5 Q6-1 Q6-2 Q6-3 Q7-1 Q7-2 Q7-3
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
# shellcheck source=script/query_common.sh
source "${SCRIPT_DIR}/query_common.sh"

resolve_query_config_source() {
    local current_suite_type="$1"
    local current_query="$2"

    printf '%s\n' "${ATMOS_PATH}/conf/${TEST_TYPE}/${sensor_type}/${current_query}"
}

prepare_query_context() {
    local current_suite_type="$1"
    local current_query="$2"
    local current_sensor_type="$3"
    local current_repeat="$4"

    ts_type="common"
    data_type="${current_suite_type}"
    query_type="${current_query}"
    sensor_type="${current_sensor_type}"
    query_num="${current_repeat}"
}

result_extra_columns() {
    printf ',sensor_type,query_num'
}

result_extra_values() {
    printf ',%s,%s' "$(sql_quote "${sensor_type}")" "${query_num}"
}

query_log_dir_suffix() {
    local current_query="$1"

    printf '%s_%s\n' "${current_query}" "${sensor_type}"
}

append_query_specific_iotdb_properties() {
    local properties_file="$1"

    printf 'query_timeout_threshold=6000000\n' >> "${properties_file}"
}

main "$@"
