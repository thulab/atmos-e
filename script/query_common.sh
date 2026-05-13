#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "query_common.sh 需要使用 bash 运行" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "query_common.sh 需要使用非 posix 模式的 bash 运行" >&2
    return 1 2>/dev/null || exit 1
fi

: "${TEST_IP:?在 source query_common.sh 之前必须设置 TEST_IP}"
: "${TEST_TYPE:?在 source query_common.sh 之前必须设置 TEST_TYPE}"

if ! declare -p PROTOCOL_LIST >/dev/null 2>&1; then
    readonly -a PROTOCOL_LIST=(211)
fi
if ! declare -p QUERY_DATA_TYPES >/dev/null 2>&1; then
    readonly -a QUERY_DATA_TYPES=(tablemode common aligned tempaligned)
fi
if ! declare -p QUERY_SENSOR_TYPES >/dev/null 2>&1; then
    readonly -a QUERY_SENSOR_TYPES=()
fi
if ! declare -p QUERY_LIST >/dev/null 2>&1; then
    readonly -a QUERY_LIST=(
        Q1 Q2-1 Q2-2 Q2-3 Q3-1 Q3-2 Q3-3 Q4a-1 Q4a-2 Q4a-3
        Q4b-1 Q4b-2 Q4b-3 Q5 Q6-1 Q6-2 Q6-3 Q7-1 Q7-2 Q7-3
        Q8 Q9-1 Q9-2 Q9-3 Q10
    )
fi
if ! declare -p QUERY_LABELS >/dev/null 2>&1; then
    readonly -a QUERY_LABELS=(
        PRECISE_POINT TIME_RANGE TIME_RANGE TIME_RANGE VALUE_RANGE VALUE_RANGE VALUE_RANGE
        AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_VALUE
        AGG_RANGE_VALUE AGG_RANGE_VALUE AGG_RANGE_VALUE GROUP_BY GROUP_BY GROUP_BY
        LATEST_POINT RANGE_QUERY_DESC RANGE_QUERY_DESC RANGE_QUERY_DESC VALUE_RANGE_QUERY_DESC
    )
fi
if ! declare -p DEFAULT_DATA_TYPE >/dev/null 2>&1; then
    readonly DEFAULT_DATA_TYPE="sequence"
else
    readonly DEFAULT_DATA_TYPE
fi
if ! declare -p QUERY_REPEAT_COUNT >/dev/null 2>&1; then
    readonly QUERY_REPEAT_COUNT=1
else
    readonly QUERY_REPEAT_COUNT
fi
if ! declare -p METRIC_SERVER >/dev/null 2>&1; then
    readonly METRIC_SERVER="172.20.70.11:9090"
else
    readonly METRIC_SERVER
fi
if ! declare -p RESULT_TABLE_NAME >/dev/null 2>&1; then
    readonly RESULT_TABLE_NAME="test_result_${TEST_TYPE}"
else
    readonly RESULT_TABLE_NAME
fi
if ! declare -p ENABLE_BENCHMARK_VERSION_CHECK >/dev/null 2>&1; then
    readonly ENABLE_BENCHMARK_VERSION_CHECK=1
else
    readonly ENABLE_BENCHMARK_VERSION_CHECK
fi
if ! declare -p BENCHMARK_WARMUP_SECONDS >/dev/null 2>&1; then
    readonly BENCHMARK_WARMUP_SECONDS=2
else
    readonly BENCHMARK_WARMUP_SECONDS
fi
if ! declare -p QUERY_DATASET_PATH >/dev/null 2>&1; then
    readonly QUERY_DATASET_PATH="${DATA_PATH:-/nasdata/${TEST_TYPE}/DataSet}"
else
    readonly QUERY_DATASET_PATH
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/runtime_common.sh
source "${SCRIPT_DIR}/runtime_common.sh"

if [ -z "${IOTDB_READY_USER:-}" ]; then
    IOTDB_READY_USER="root"
fi
if [ -z "${IOTDB_READY_PASSWORD:-}" ]; then
    IOTDB_READY_PASSWORD="${IOTDB_PW:-root}"
fi

query_type=""
query_label_name=""
query_suite_type=""
sensor_type=""
query_num=1

init_items() {
    init_common_items
    ts_type=""
    data_type="${DEFAULT_DATA_TYPE}"
    query_type=""
    query_label_name=""
    query_suite_type=""
    sensor_type=""
    query_num=1
}

validate_query_settings() {
    [[ "${QUERY_REPEAT_COUNT}" =~ ^[1-9][0-9]*$ ]] || die "QUERY_REPEAT_COUNT 必须是正整数"
    [ "${#QUERY_LIST[@]}" -eq "${#QUERY_LABELS[@]}" ] || die "QUERY_LIST 和 QUERY_LABELS 的数量不一致"
}

resolve_query_dataset_source() {
    local protocol_code="$1"
    local current_suite_type="$2"

    printf '%s\n' "${QUERY_DATASET_PATH}/${protocol_code}/${current_suite_type}/data"
}

resolve_query_config_source() {
    local current_suite_type="$1"
    local current_query="$2"
    local current_sensor_type="${3:-}"
    local config_root="${ATMOS_PATH}/conf/${TEST_TYPE}"
    local -a search_roots=()
    local resolved_path=""

    if [ -n "${current_suite_type}" ] && [ -n "${current_sensor_type}" ]; then
        search_roots+=("${config_root}/query/${current_suite_type}/${current_sensor_type}")
    fi
    if [ -n "${current_suite_type}" ]; then
        search_roots+=("${config_root}/query/${current_suite_type}")
    fi
    if [ -n "${current_sensor_type}" ]; then
        search_roots+=("${config_root}/query/${current_sensor_type}")
    fi
    search_roots+=("${config_root}/query")

    if [ -n "${current_suite_type}" ] && [ -n "${current_sensor_type}" ]; then
        search_roots+=("${config_root}/${current_suite_type}/${current_sensor_type}")
    fi
    if [ -n "${current_suite_type}" ]; then
        search_roots+=("${config_root}/${current_suite_type}")
    fi
    if [ -n "${current_sensor_type}" ]; then
        search_roots+=("${config_root}/${current_sensor_type}")
    fi
    search_roots+=("${config_root}")

    resolved_path="$(resolve_config_from_roots "${current_query}" "${search_roots[@]}")" || \
        die "缺少 benchmark 配置文件: ${current_query} (suite=${current_suite_type:-default}, sensor=${current_sensor_type:-default})"
    printf '%s\n' "${resolved_path}"
}

prepare_query_context() {
    local current_suite_type="$1"
    local current_query="$2"
    local current_sensor_type="$3"
    local current_repeat="$4"
    local current_query_label="${5:-}"

    ts_type="${current_suite_type}"
    data_type="${DEFAULT_DATA_TYPE}"
    query_type="$(normalize_query_name "${current_query}")"
    query_label_name="${current_query_label}"
    query_suite_type="${current_suite_type}"
    sensor_type="${current_sensor_type}"
    query_num="${current_repeat}"
}

result_extra_columns() {
    :
}

result_extra_values() {
    :
}

query_log_dir_suffix() {
    local current_query="$1"

    if [ -n "${sensor_type:-}" ]; then
        printf '%s_%s\n' "${current_query}" "${sensor_type}"
    else
        printf '%s\n' "${current_query}"
    fi
}

append_query_specific_iotdb_properties() {
    local properties_file="$1"

    :
}

append_iotdb_properties() {
    local properties_file="$1"

    cat >> "${properties_file}" <<EOF
series_slot_num=10000
enable_seq_space_compaction=false
enable_unseq_space_compaction=false
enable_cross_space_compaction=false
EOF

    append_query_specific_iotdb_properties "${properties_file}"
}

copy_query_dataset() {
    local protocol_code="$1"
    local current_suite_type="$2"
    local source_path=""

    source_path="$(resolve_query_dataset_source "${protocol_code}" "${current_suite_type}")"
    [ -d "${source_path}" ] || die "缺少查询数据集: ${source_path}"
    cp -rf -- "${source_path}" "${TEST_IOTDB_PATH}/"
}

collect_monitor_data() {
    local ip="${1:-${TEST_IP}}"

    collect_common_monitor_data "${ip}"
}

legacy_backup_test_data_compat() {
    local current_suite_type="$1"
    local backup_parent="${BACKUP_PATH}/${current_suite_type}"
    local backup_dir="${backup_parent}/${commit_date_time}_${commit_id}"

    sudo_safe_rm "${backup_dir}"
    path_is_safe "${backup_parent}" || die "拒绝使用非预期备份路径: ${backup_parent}"
    sudo mkdir -p -- "${backup_parent}"
    path_is_safe "${backup_dir}" || die "拒绝使用非预期备份路径: ${backup_dir}"
    sudo mkdir -p -- "${backup_dir}"

    sudo_safe_rm "${TEST_IOTDB_PATH}/data"
    path_is_safe "${TEST_IOTDB_PATH}" || die "拒绝移动非预期路径: ${TEST_IOTDB_PATH}"
    sudo mv "${TEST_IOTDB_PATH}" "${backup_dir}"
    sudo cp -rf "${BM_PATH}/data/csvOutput" "${backup_dir}"
}

legacy_mv_config_file_compat() {
    local current_suite_type="$1"
    local current_query="$2"

    copy_benchmark_config "$(resolve_query_config_source "${current_suite_type}" "${current_query}")"
}

backup_test_data() {
    local protocol_code="$1"
    local current_suite_type="$2"
    local backup_dir=""

    backup_dir="$(build_scoped_path \
        "${BACKUP_PATH}" \
        "protocol=${protocol_code}" \
        "suite=${current_suite_type}" \
        "commit=${commit_date_time}_${commit_id}")"
    archive_test_runtime_artifacts "${backup_dir}"
}

mv_config_file() {
    local current_suite_type="$1"
    local current_query="$2"
    local current_sensor_type="${3:-}"

    copy_benchmark_config "$(resolve_query_config_source "${current_suite_type}" "${current_query}" "${current_sensor_type}")"
}

append_tablemode_config_if_needed() {
    local current_suite_type="$1"

    if [ "${current_suite_type}" = "tablemode" ]; then
        printf 'IoTDB_DIALECT_MODE=table\n' >> "${BM_PATH}/conf/config.properties"
    fi
}

parse_query_result() {
    local csv_file="$1"
    local query_label="$2"
    local throughput_line=""
    local latency_line=""

    [ -f "${csv_file}" ] || return 1

    throughput_line="$(
        awk -F, -v query_label="${query_label}" '
            function trim_field(value) {
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                return value
            }
            trim_field($1) == query_label {
                for (i = 2; i <= 6; i++) {
                    value = trim_field($i)
                    printf "%s%s", value, (i == 6 ? ORS : OFS)
                }
                exit
            }
        ' OFS=$'\t' "${csv_file}"
    )"

    latency_line="$(
        awk -F, -v query_label="${query_label}" '
            function trim_field(value) {
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                return value
            }
            trim_field($1) == query_label {
                count++
                if (count == 2) {
                    for (i = 2; i <= 12; i++) {
                        value = trim_field($i)
                        printf "%s%s", value, (i == 12 ? ORS : OFS)
                    }
                    exit
                }
            }
        ' OFS=$'\t' "${csv_file}"
    )"

    [ -n "${throughput_line}" ] || return 1
    [ -n "${latency_line}" ] || return 1

    IFS=$'\t' read -r okOperation okPoint failOperation failPoint throughput <<< "${throughput_line}"
    IFS=$'\t' read -r Latency MIN P10 P25 MEDIAN P75 P90 P95 P99 P999 MAX <<< "${latency_line}"
}

insert_result_row() {
    local protocol_code="$1"
    local extra_columns=""
    local extra_values=""
    local insert_sql=""

    extra_columns="$(result_extra_columns)"
    extra_values="$(result_extra_values)"
    insert_sql=$(cat <<EOF
insert into ${RESULT_TABLE_NAME} (
    commit_date_time,test_date_time,commit_id,author,ts_type,data_type,query_type,
    okPoint,okOperation,failPoint,failOperation,throughput,Latency,MIN,P10,P25,
    MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,
    numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,errorLogSize,walFileSize,
    avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,
    protocol_code,query_suite_type,query_sensor_type,query_repeat_no,query_id,query_label,result_kind,remark${extra_columns}
) values (
    ${commit_date_time},
    ${test_date_time},
    $(sql_quote "${commit_id}"),
    $(sql_quote "${author}"),
    $(sql_quote "${ts_type}"),
    $(sql_quote "${data_type}"),
    $(sql_quote "${query_type}"),
    ${okPoint},
    ${okOperation},
    ${failPoint},
    ${failOperation},
    ${throughput},
    ${Latency},
    ${MIN},
    ${P10},
    ${P25},
    ${MEDIAN},
    ${P75},
    ${P90},
    ${P95},
    ${P99},
    ${P999},
    ${MAX},
    ${numOfSe0Level},
    $(sql_quote "${start_time}"),
    $(sql_quote "${end_time}"),
    ${cost_time},
    ${numOfUnse0Level},
    ${dataFileSize},
    ${maxNumofOpenFiles},
    ${maxNumofThread},
    ${errorLogSize},
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    $(sql_quote "${protocol_code}"),
    $(sql_maybe_quote "${query_suite_type}"),
    $(sql_maybe_quote "${sensor_type}"),
    ${query_num},
    $(sql_maybe_quote "${query_type}"),
    $(sql_maybe_quote "${query_label_name}"),
    'query',
    $(sql_quote "${protocol_code}")${extra_values}
)
EOF
)

    mysql_exec "${insert_sql}"
}

archive_query_logs() {
    local current_query="$1"
    local log_suffix=""
    local live_log_dir="${TEST_IOTDB_PATH}/logs"
    local archived_log_dir=""

    log_suffix="$(query_log_dir_suffix "${current_query}")"
    archived_log_dir="${TEST_IOTDB_PATH}/logs_${log_suffix}"
    [ -d "${live_log_dir}" ] || mkdir -p "${live_log_dir}"
    [ -d "${BM_PATH}/data/csvOutput" ] || return 0

    safe_rm "${archived_log_dir}"
    cp -rf "${BM_PATH}/data/csvOutput" "${live_log_dir}/"
    mv "${live_log_dir}" "${archived_log_dir}"
}

test_operation() {
    local protocol_code="$1"
    local current_suite_type=""
    local current_query=""
    local current_sensor_type=""
    local current_repeat=0
    local query_label=""
    local query_scope=""
    local csv_file=""
    local index=0
    local monitor_failed=0
    local operation_failed=0
    local -a sensor_types=()

    if [ "${#QUERY_SENSOR_TYPES[@]}" -gt 0 ]; then
        sensor_types=("${QUERY_SENSOR_TYPES[@]}")
    else
        sensor_types=("")
    fi

    for current_suite_type in "${QUERY_DATA_TYPES[@]}"; do
        log "开始执行协议 ${protocol_code}、查询场景 ${current_suite_type} 的查询测试"
        cleanup_processes
        set_env
        modify_iotdb_config

        if ! set_protocol_class "${protocol_code}"; then
            log "协议配置无效: ${protocol_code}"
            return 1
        fi

        copy_query_dataset "${protocol_code}" "${current_suite_type}"

        for current_sensor_type in "${sensor_types[@]}"; do
            for ((index = 0; index < ${#QUERY_LIST[@]}; index++)); do
                current_query="${QUERY_LIST[${index}]}"
                query_label="${QUERY_LABELS[${index}]}"
                query_scope="${current_query}"
                if [ -n "${current_sensor_type}" ]; then
                    query_scope="${query_scope}/${current_sensor_type}"
                fi

                log "开始执行 ${current_suite_type} 的 ${query_scope} 查询"
                check_iotdb_pid
                sleep 1
                start_iotdb
                sleep "${STARTUP_GRACE_SECONDS}"

                if ! wait_for_iotdb_ready; then
                    init_items
                    prepare_query_context "${current_suite_type}" "${current_query}" "${current_sensor_type}" 1 "${query_label}"
                    log "IoTDB 未能正常启动，记录失败结果"
                    end_time="$(current_datetime)"
                    cost_time=-3
                    throughput=-3
                    insert_result_row "${protocol_code}"
                    operation_failed=1
                    stop_iotdb
                    sleep "${BENCHMARK_STOP_WAIT_SECONDS}"
                    cleanup_processes
                    continue
                fi

                mv_config_file "${current_suite_type}" "${current_query}" "${current_sensor_type}"
                append_tablemode_config_if_needed "${current_suite_type}"
                sleep 3

                for ((current_repeat = 1; current_repeat <= QUERY_REPEAT_COUNT; current_repeat++)); do
                    init_items
                    prepare_query_context "${current_suite_type}" "${current_query}" "${current_sensor_type}" "${current_repeat}" "${query_label}"
                    monitor_failed=0

                    start_benchmark
                    start_time="$(current_datetime)"
                    m_start_time="$(date +%s)"
                    sleep "${BENCHMARK_WARMUP_SECONDS}"

                    if ! monitor_test_status "${current_query}" "${query_label}"; then
                        monitor_failed=1
                    fi

                    m_end_time="$(date +%s)"
                    collect_monitor_data "${TEST_IP}"

                    csv_file="$(find_result_csv || true)"
                    if [ -z "${csv_file}" ] || ! parse_query_result "${csv_file}" "${query_label}"; then
                        log "benchmark 结果解析失败，记录兜底失败结果"
                        [ -n "${end_time}" ] || end_time="$(current_datetime)"
                        cost_time=-2
                        throughput=-2
                        insert_result_row "${protocol_code}"
                        operation_failed=1
                        if [ "${monitor_failed}" -ne 0 ]; then
                            operation_failed=1
                        fi
                        continue
                    fi

                    [ -n "${end_time}" ] || end_time="$(current_datetime)"
                    cost_time=$(( $(datetime_to_epoch "${end_time}") - $(datetime_to_epoch "${start_time}") ))
                    insert_result_row "${protocol_code}"
                    log "${commit_id} ${ts_type} ${query_scope} 第${query_num}次: ${okPoint} 个点耗时 ${Latency} ms"

                    if [ "${monitor_failed}" -ne 0 ]; then
                        operation_failed=1
                    fi
                done

                archive_query_logs "${current_query}"
                stop_iotdb
                sleep "${BENCHMARK_STOP_WAIT_SECONDS}"
                cleanup_processes
            done
        done

        log "${current_suite_type} 查询测试已完成"
        [ -d "${TEST_IOTDB_PATH}" ] && backup_test_data "${protocol_code}" "${current_suite_type}"
    done

    return "${operation_failed}"
}

main() {
    local protocol=""
    local task_failed=0

    trap restore_test_type_file EXIT

    ensure_runtime_dependencies
    check_password
    validate_query_settings
    if [ "${ENABLE_BENCHMARK_VERSION_CHECK}" = "1" ]; then
        check_benchmark_version
    fi

    mark_test_in_progress
    if ! fetch_next_commit; then
        sleep 60
        return 0
    fi

    update_task_status "ontesting"
    log "当前版本 ${commit_id} 未执行过测试，开始查询测试流程"

    test_date_time="$(date +%Y%m%d%H%M%S)"
    for protocol in "${PROTOCOL_LIST[@]}"; do
        if ! test_operation "${protocol}"; then
            task_failed=1
        fi
    done

    log "本轮查询测试 ${test_date_time} 已结束"
    if [ "${task_failed}" -eq 0 ]; then
        update_task_status "done"
        mark_older_commits_skip
    else
        update_task_status "RError"
    fi
}
