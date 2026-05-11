#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="172.20.31.64"
readonly TEST_TYPE="routine_test"
readonly IOTDB_PW="TimechoDB@2021"
readonly RESULT_TABLE_NAME="test_result_${TEST_TYPE}"
readonly METRIC_SERVER="172.20.70.11:9090"
readonly MONITOR_TIMEOUT_SECONDS=72000
readonly BENCHMARK_WARMUP_SECONDS=10
readonly QUERY_STARTUP_EXTRA_WAIT_SECONDS=20
readonly MONITOR_DISK_ID="vdc"

readonly -a PROTOCOL_LIST=(223 111)
readonly -a INSERT_CONFIGS=(seq_w unseq_w seq_rw unseq_rw)
readonly -a QUERY_LIST=(
    Q1 Q2-1 Q2-2 Q2-3 Q3-1 Q3-2 Q3-3 Q4-a1 Q4-a2 Q4-a3
    Q4-b1 Q4-b2 Q4-b3 Q5 Q6-1 Q6-2 Q6-3 Q7-1 Q7-2 Q7-3
    Q7-4 Q8 Q9 Q10
)
readonly -a QUERY_LABELS=(
    PRECISE_POINT TIME_RANGE TIME_RANGE TIME_RANGE VALUE_RANGE VALUE_RANGE VALUE_RANGE
    AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_VALUE
    AGG_RANGE_VALUE AGG_RANGE_VALUE AGG_RANGE_VALUE GROUP_BY GROUP_BY GROUP_BY
    GROUP_BY LATEST_POINT RANGE_QUERY_DESC VALUE_RANGE_QUERY_DESC
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/runtime_common.sh
source "${SCRIPT_DIR}/runtime_common.sh"

op_type=""
current_protocol_code=""
maxCPULoad=0
avgCPULoad=0
maxDiskIOOpsRead=0
maxDiskIOOpsWrite=0
maxDiskIOSizeRead=0
maxDiskIOSizeWrite=0

init_items() {
    init_common_items
    maxCPULoad=0
    avgCPULoad=0
    maxDiskIOOpsRead=0
    maxDiskIOOpsWrite=0
    maxDiskIOSizeRead=0
    maxDiskIOSizeWrite=0
}

change_root_password() {
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" -e "ALTER USER root SET PASSWORD '${IOTDB_PW}'" >/dev/null 2>&1
}

flush_iotdb() {
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" -u root -pw "${IOTDB_PW}" -h 127.0.0.1 -p 6667 -e "flush" >/dev/null 2>&1
}

resolve_config_source() {
    local config_name="$1"

    printf '%s\n' "${ATMOS_PATH}/conf/${TEST_TYPE}/${config_name}"
}

copy_routine_config() {
    local config_name="$1"

    copy_benchmark_config "$(resolve_config_source "${config_name}")"
}

collect_monitor_data() {
    local metric_window=$((m_end_time - m_start_time))

    if [ "${metric_window}" -le 0 ]; then
        metric_window=1
    fi

    collect_common_monitor_data "${TEST_IP}"
    maxCPULoad="$(get_single_index "max_over_time(sys_cpu_load{instance=~\"${TEST_IP}:9091\"}[${metric_window}s])" "${m_end_time}")"
    avgCPULoad="$(get_single_index "avg_over_time(sys_cpu_load{instance=~\"${TEST_IP}:9091\"}[${metric_window}s])" "${m_end_time}")"
    maxDiskIOOpsRead="$(get_single_index "rate(disk_io_ops{instance=~\"${TEST_IP}:9091\",disk_id=~\"${MONITOR_DISK_ID}\",type=~\"read\"}[${metric_window}s])" "${m_end_time}")"
    maxDiskIOOpsWrite="$(get_single_index "rate(disk_io_ops{instance=~\"${TEST_IP}:9091\",disk_id=~\"${MONITOR_DISK_ID}\",type=~\"write\"}[${metric_window}s])" "${m_end_time}")"
    maxDiskIOSizeRead="$(get_single_index "rate(disk_io_size{instance=~\"${TEST_IP}:9091\",disk_id=~\"${MONITOR_DISK_ID}\",type=~\"read\"}[${metric_window}s])" "${m_end_time}")"
    maxDiskIOSizeWrite="$(get_single_index "rate(disk_io_size{instance=~\"${TEST_IP}:9091\",disk_id=~\"${MONITOR_DISK_ID}\",type=~\"write\"}[${metric_window}s])" "${m_end_time}")"
}

backup_test_data() {
    local current_insert_type="$1"
    local backup_parent="${BACKUP_PATH}/${current_insert_type}"
    local backup_dir="${backup_parent}/${commit_date_time}_${commit_id}_${current_protocol_code}"

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

parse_ingestion_result() {
    local csv_file="$1"
    local throughput_line=""
    local latency_line=""

    [ -f "${csv_file}" ] || return 1

    throughput_line="$(
        awk -F, '
            /^INGESTION/ {
                for (i = 2; i <= 6; i++) {
                    gsub(/^[ \t]+|[ \t]+$/, "", $i)
                    printf "%s%s", $i, (i == 6 ? ORS : OFS)
                }
                exit
            }
        ' OFS=$'\t' "${csv_file}"
    )"

    latency_line="$(
        awk -F, '
            /^INGESTION/ {
                count++
                if (count == 2) {
                    for (i = 2; i <= 12; i++) {
                        gsub(/^[ \t]+|[ \t]+$/, "", $i)
                        printf "%s%s", $i, (i == 12 ? ORS : OFS)
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
    local insert_sql=""

    insert_sql=$(cat <<EOF
insert into ${RESULT_TABLE_NAME} (
    commit_date_time,test_date_time,commit_id,author,ts_type,data_type,op_type,okPoint,okOperation,failPoint,
    failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,
    end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,errorLogSize,walFileSize,
    avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,remark
) values (
    ${commit_date_time},
    ${test_date_time},
    $(sql_quote "${commit_id}"),
    $(sql_quote "${author}"),
    $(sql_quote "${ts_type}"),
    $(sql_quote "${data_type}"),
    $(sql_quote "${op_type}"),
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
    ${walFileSize},
    ${avgCPULoad},
    ${maxCPULoad},
    ${maxDiskIOSizeRead},
    ${maxDiskIOSizeWrite},
    ${maxDiskIOOpsRead},
    ${maxDiskIOOpsWrite},
    $(sql_quote "${current_protocol_code}")
)
EOF
)

    mysql_exec "${insert_sql}"
}

record_failure_result() {
    local failure_code="$1"

    [ -n "${end_time}" ] || end_time="$(current_datetime)"
    cost_time="${failure_code}"
    throughput="${failure_code}"
    insert_result_row
}

run_benchmark_case() {
    local current_name="$1"
    local result_label="$2"
    local parse_mode="$3"
    local flush_before_collect="${4:-0}"
    local csv_file=""
    local monitor_failed=0

    start_benchmark
    start_time="$(current_datetime)"
    m_start_time="$(date +%s)"
    sleep "${BENCHMARK_WARMUP_SECONDS}"

    if ! monitor_test_status "${current_name}" "${result_label}"; then
        monitor_failed=1
    fi

    m_end_time="$(date +%s)"
    if [ "${flush_before_collect}" = "1" ]; then
        flush_iotdb || true
    fi
    collect_monitor_data

    csv_file="$(find_result_csv || true)"
    case "${parse_mode}" in
        ingestion)
            if [ -z "${csv_file}" ] || ! parse_ingestion_result "${csv_file}"; then
                log "${current_name} 结果解析失败，记录兜底失败结果"
                record_failure_result -2
                return 1
            fi
            ;;
        query)
            if [ -z "${csv_file}" ] || ! parse_query_result "${csv_file}" "${result_label}"; then
                log "${current_name} 结果解析失败，记录兜底失败结果"
                record_failure_result -2
                return 1
            fi
            ;;
        *)
            die "未知解析模式: ${parse_mode}"
            ;;
    esac

    [ -n "${end_time}" ] || end_time="$(current_datetime)"
    cost_time=$(( $(datetime_to_epoch "${end_time}") - $(datetime_to_epoch "${start_time}") ))
    insert_result_row

    if [ "${monitor_failed}" -ne 0 ]; then
        return 1
    fi

    return 0
}

run_query_case() {
    local current_query="$1"
    local query_label="$2"
    local query_failed=0

    init_items
    ts_type="common"
    op_type="${current_query}"
    IOTDB_READY_USER="root"
    IOTDB_READY_PASSWORD="${IOTDB_PW}"

    log "开始执行 ${data_type} 数据的 ${current_query} 查询"
    check_iotdb_pid
    sleep 1
    start_iotdb
    sleep "${QUERY_STARTUP_EXTRA_WAIT_SECONDS}"

    if ! wait_for_iotdb_ready; then
        log "IoTDB 未能正常启动，记录查询失败结果"
        record_failure_result -3
        stop_iotdb
        sleep "${BENCHMARK_STOP_WAIT_SECONDS}"
        cleanup_processes
        return 1
    fi

    copy_routine_config "${current_query}"
    if ! run_benchmark_case "${current_query}" "${query_label}" query 0; then
        query_failed=1
    fi

    stop_iotdb
    sleep "${BENCHMARK_STOP_WAIT_SECONDS}"
    cleanup_processes
    return "${query_failed}"
}

run_insert_case() {
    local current_insert_type="$1"
    local query_index=0
    local case_failed=0

    init_items
    ts_type="common"
    data_type="${current_insert_type}"
    op_type="INGESTION"

    log "开始执行协议 ${current_protocol_code} 的 ${current_insert_type} 插入测试"
    cleanup_processes
    set_env
    modify_iotdb_config

    if ! set_protocol_class "${current_protocol_code}"; then
        log "协议配置无效: ${current_protocol_code}"
        return 1
    fi

    IOTDB_READY_USER=""
    IOTDB_READY_PASSWORD=""
    start_iotdb
    if ! wait_for_iotdb_ready; then
        log "IoTDB 未能正常启动，记录插入失败结果"
        record_failure_result -3
        cleanup_processes
        return 1
    fi

    if ! change_root_password; then
        log "root 密码修改失败，记录插入失败结果"
        record_failure_result -4
        stop_iotdb
        sleep "${BENCHMARK_STOP_WAIT_SECONDS}"
        cleanup_processes
        return 1
    fi

    IOTDB_READY_USER="root"
    IOTDB_READY_PASSWORD="${IOTDB_PW}"
    copy_routine_config "${current_insert_type}"
    if ! run_benchmark_case "${current_insert_type}" "INGESTION" ingestion 1; then
        case_failed=1
    fi

    stop_iotdb
    sleep "${BENCHMARK_STOP_WAIT_SECONDS}"
    cleanup_processes

    if [ "${case_failed}" -ne 0 ]; then
        [ -d "${TEST_IOTDB_PATH}" ] && backup_test_data "${current_insert_type}"
        return 1
    fi

    for ((query_index = 0; query_index < ${#QUERY_LIST[@]}; query_index++)); do
        if ! run_query_case "${QUERY_LIST[${query_index}]}" "${QUERY_LABELS[${query_index}]}"; then
            case_failed=1
        fi
    done

    [ -d "${TEST_IOTDB_PATH}" ] && backup_test_data "${current_insert_type}"
    return "${case_failed}"
}

test_operation() {
    local protocol_code="$1"
    local current_insert_type=""
    local operation_failed=0

    current_protocol_code="${protocol_code}"
    for current_insert_type in "${INSERT_CONFIGS[@]}"; do
        if ! run_insert_case "${current_insert_type}"; then
            operation_failed=1
        fi
    done

    return "${operation_failed}"
}

main() {
    local protocol=""
    local task_failed=0

    trap restore_test_type_file EXIT

    ensure_runtime_dependencies
    check_password
    [ "${#QUERY_LIST[@]}" -eq "${#QUERY_LABELS[@]}" ] || die "QUERY_LIST 和 QUERY_LABELS 的数量不一致"
    if [ "${ENABLE_BENCHMARK_VERSION_CHECK}" = "1" ]; then
        check_benchmark_version
    fi

    mark_test_in_progress
    if ! fetch_next_commit; then
        sleep 60
        return 0
    fi

    update_task_status "ontesting"
    log "当前版本 ${commit_id} 未执行过测试，开始 routine_test 流程"

    test_date_time="$(date +%Y%m%d%H%M%S)"
    for protocol in "${PROTOCOL_LIST[@]}"; do
        if ! test_operation "${protocol}"; then
            task_failed=1
        fi
    done

    log "本轮 routine_test ${test_date_time} 已结束"
    if [ "${task_failed}" -eq 0 ]; then
        update_task_status "done"
        mark_older_commits_skip
    else
        update_task_status "RError"
    fi
}

main "$@"
