#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="${TREEVIEW_QUERY_TEST_IP:-172.20.31.12}"
readonly TEST_TYPE="treeview_query"
readonly IOTDB_PW="${TREEVIEW_IOTDB_PW:-root}"
readonly -a PROTOCOL_LIST=(211)
readonly -a QUERY_LIST=(
    Q1 Q2-1 Q2-2 Q2-3 Q3-1 Q3-2 Q3-3 Q4a-1 Q4a-2 Q4a-3
    Q4b-1 Q4b-2 Q4b-3 Q5 Q6-1 Q6-2 Q6-3 Q7-1 Q7-2 Q7-3
    Q8 Q9-1 Q9-2 Q9-3 Q10
)
readonly -a QUERY_LABELS=(
    PRECISE_POINT TIME_RANGE TIME_RANGE TIME_RANGE VALUE_RANGE VALUE_RANGE VALUE_RANGE
    AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_VALUE
    AGG_RANGE_VALUE AGG_RANGE_VALUE AGG_RANGE_VALUE GROUP_BY GROUP_BY GROUP_BY
    LATEST_POINT RANGE_QUERY_DESC RANGE_QUERY_DESC RANGE_QUERY_DESC VALUE_RANGE_QUERY_DESC
)

if [ -n "${TREEVIEW_QUERY_SUITES:-}" ]; then
    IFS=',' read -r -a QUERY_DATA_TYPES <<< "${TREEVIEW_QUERY_SUITES}"
    readonly -a QUERY_DATA_TYPES
else
    readonly -a QUERY_DATA_TYPES=(
        seq_common
        seq_aligned
        seq_tempaligned
        unseq_common
        unseq_aligned
        unseq_tempaligned
    )
fi

readonly METRIC_SERVER="${TREEVIEW_METRIC_SERVER:-172.20.70.11:9090}"
readonly QUERY_REPEAT_COUNT="${TREEVIEW_QUERY_REPEAT_COUNT:-1}"
readonly BENCHMARK_WARMUP_SECONDS="${TREEVIEW_BENCHMARK_WARMUP_SECONDS:-2}"
readonly SE_QUERY_DATASET_PATH="${TREEVIEW_SE_QUERY_DATASET_PATH:-/nasdata/se_query/DataSet}"
readonly UNSE_QUERY_DATASET_PATH="${TREEVIEW_UNSE_QUERY_DATASET_PATH:-/nasdata/unse_query/DataSet}"
IOTDB_READY_PASSWORD="${IOTDB_PW}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/query_common.sh
source "${SCRIPT_DIR}/query_common.sh"

TREEVIEW_DB_NAME="${TREEVIEW_DB_NAME:-test}"
TREEVIEW_GROUP_NAME_PREFIX="${TREEVIEW_GROUP_NAME_PREFIX:-g_}"
TREEVIEW_TABLE_NAME_PREFIX="${TREEVIEW_TABLE_NAME_PREFIX:-table_}"
TREEVIEW_GROUP_INDEX="${TREEVIEW_GROUP_INDEX:-0}"
TREEVIEW_TABLE_DATABASE="${TREEVIEW_TABLE_DATABASE:-${TREEVIEW_DB_NAME}_${TREEVIEW_GROUP_NAME_PREFIX}${TREEVIEW_GROUP_INDEX}}"
TREEVIEW_TABLE_NAME="${TREEVIEW_TABLE_NAME:-${TREEVIEW_TABLE_NAME_PREFIX}0}"
TREEVIEW_TREE_PREFIX="${TREEVIEW_TREE_PREFIX:-root.${TREEVIEW_DB_NAME}.${TREEVIEW_GROUP_NAME_PREFIX}${TREEVIEW_GROUP_INDEX}}"

treeview_base_suite() {
    local current_suite_type="$1"

    case "${current_suite_type}" in
        seq_common|unseq_common)
            printf 'common\n'
            ;;
        seq_aligned|unseq_aligned)
            printf 'aligned\n'
            ;;
        seq_tempaligned|unseq_tempaligned)
            printf 'tempaligned\n'
            ;;
        *)
            die "unsupported treeview query suite: ${current_suite_type}"
            ;;
    esac
}

treeview_config_suite() {
    local current_suite_type="$1"

    case "${current_suite_type}" in
        seq_*)
            printf 'seq\n'
            ;;
        unseq_*)
            printf 'unseq\n'
            ;;
        *)
            die "unsupported treeview query suite: ${current_suite_type}"
            ;;
    esac
}

treeview_dataset_root() {
    local current_suite_type="$1"

    case "${current_suite_type}" in
        seq_*)
            printf '%s\n' "${SE_QUERY_DATASET_PATH}"
            ;;
        unseq_*)
            printf '%s\n' "${UNSE_QUERY_DATASET_PATH}"
            ;;
        *)
            die "unsupported treeview query suite: ${current_suite_type}"
            ;;
    esac
}

treeview_source_data_type() {
    local current_suite_type="$1"

    case "${current_suite_type}" in
        seq_*)
            printf 'sequence\n'
            ;;
        unseq_*)
            printf 'unsequence\n'
            ;;
        *)
            die "unsupported treeview query suite: ${current_suite_type}"
            ;;
    esac
}

resolve_query_dataset_source() {
    local protocol_code="$1"
    local current_suite_type="$2"
    local base_suite=""
    local dataset_root=""

    base_suite="$(treeview_base_suite "${current_suite_type}")"
    dataset_root="$(treeview_dataset_root "${current_suite_type}")"
    printf '%s/%s/%s/data\n' "${dataset_root}" "${protocol_code}" "${base_suite}"
}

resolve_query_config_source() {
    local current_suite_type="$1"
    local current_query="$2"
    local current_sensor_type="${3:-}"
    local config_suite=""
    local config_root=""
    local resolved_path=""

    config_suite="$(treeview_config_suite "${current_suite_type}")"
    config_root="${ATMOS_PATH}/conf/${TEST_TYPE}/query/${config_suite}"
    resolved_path="$(resolve_config_from_roots "${current_query}" "${config_root}")" || \
        die "missing treeview benchmark config: ${current_query} (suite=${current_suite_type}, sensor=${current_sensor_type:-default})"
    printf '%s\n' "${resolved_path}"
}

prepare_query_context() {
    local current_suite_type="$1"
    local current_query="$2"
    local current_sensor_type="$3"
    local current_repeat="$4"
    local current_query_label="${5:-}"
    local base_suite=""

    base_suite="$(treeview_base_suite "${current_suite_type}")"
    ts_type="treeview_${base_suite}"
    data_type="$(treeview_source_data_type "${current_suite_type}")"
    query_type="$(normalize_query_name "${current_query}")"
    query_label_name="${current_query_label}"
    query_suite_type="${current_suite_type}"
    sensor_type="${current_sensor_type}"
    query_num="${current_repeat}"
}

append_tablemode_config_if_needed() {
    local current_suite_type="$1"

    cat >> "${BM_PATH}/conf/config.properties" <<EOF
IoTDB_DIALECT_MODE=table
DB_NAME=${TREEVIEW_DB_NAME}
GROUP_NAME_PREFIX=${TREEVIEW_GROUP_NAME_PREFIX}
IoTDB_TABLE_NAME_PREFIX=${TREEVIEW_TABLE_NAME_PREFIX}
IoTDB_TABLE_NUMBER=1
EOF
}

treeview_cli_sql() {
    local sql="$1"
    local output=""
    local status=0
    local user="${IOTDB_READY_USER:-root}"
    local password="${IOTDB_READY_PASSWORD:-${IOTDB_PW}}"
    local -a cmd=(
        "${TEST_IOTDB_PATH}/sbin/start-cli.sh"
        -u "${user}"
        -pw "${password}"
        -sql_dialect table
        -h 127.0.0.1
        -p 6667
        -e "${sql}"
    )

    output="$("${cmd[@]}" 2>&1)"
    status=$?
    if [ "${status}" -ne 0 ]; then
        log "failed to execute table sql: ${sql}"
        log "${output}"
        return "${status}"
    fi
    printf '%s\n' "${output}"
}

prepare_tree_to_table_view() {
    local current_suite_type="$1"
    local view_name="${TREEVIEW_TABLE_DATABASE}.${TREEVIEW_TABLE_NAME}"
    local source_path="${TREEVIEW_TREE_PREFIX}.**"

    log "prepare Tree-to-Table view ${view_name} from ${source_path} for ${current_suite_type}"
    treeview_cli_sql "CREATE DATABASE IF NOT EXISTS ${TREEVIEW_TABLE_DATABASE}" >/dev/null || return 1
    treeview_cli_sql "CREATE OR REPLACE VIEW ${view_name} (device_id STRING TAG) AS ${source_path}" >/dev/null || return 1
    treeview_cli_sql "SHOW CREATE VIEW ${view_name}" >/dev/null || return 1
    treeview_cli_sql "SELECT count(s_0) FROM ${view_name} WHERE device_id = 'd_0'" >/dev/null || return 1
}

mv_config_file() {
    local current_suite_type="$1"
    local current_query="$2"
    local current_sensor_type="${3:-}"

    prepare_tree_to_table_view "${current_suite_type}" || die "failed to prepare Tree-to-Table view for ${current_suite_type}"
    copy_benchmark_config "$(resolve_query_config_source "${current_suite_type}" "${current_query}" "${current_sensor_type}")"
}

main "$@"
