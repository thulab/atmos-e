#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_TYPE="ts_performance"
readonly TEST_IP="172.20.31.8"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/runtime_common.sh
source "${SCRIPT_DIR}/runtime_common.sh"

readonly DATASET_PATH="/nasdata/${TEST_TYPE}/DataSet"
readonly LIVE_LOG_DIR="${TEST_IOTDB_PATH}/tools/testlog"
readonly LIVE_LOG_FILE="${LIVE_LOG_DIR}/log.txt"
readonly EXPORT_DATA_DIR="${TEST_IOTDB_PATH}/tools/data"
readonly EXPORT_SEQUENCE_DIR="${EXPORT_DATA_DIR}/datanode/data/sequence"
readonly TABLEMODE_DATABASE="test_g_0"
readonly TABLEMODE_TABLE="table_0"
readonly TABLEMODE_SCHEMA_FILE="${ATMOS_PATH}/conf/${TEST_TYPE}/metadata/dump_test_g_0.sql"
readonly TABLENAME="test_result_${TEST_TYPE}"
readonly STOP_WAIT_SECONDS=30
readonly OPERATION_WARMUP_SECONDS=30
readonly -a PROTOCOL_LIST=(223)
readonly -a TEST_CASES=(
    "common:sequence"
    "common:unsequence"
    "aligned:sequence"
    "aligned:unsequence"
    "tempaligned:sequence"
    "tempaligned:unsequence"
    "tablemode:sequence"
    "tablemode:unsequence"
)

numOfSe0Level_before=0
numOfSe0Level_after=0
numOfUnse0Level_before=0
numOfUnse0Level_after=0
ts_dataSize=0
ts_numOfPoints=0
ts_rate=0
dataFileSize_before=0
dataFileSize_after=0
operation_pid=0
export_properties_applied=0

append_iotdb_properties() {
    local properties_file="$1"

    cat >> "${properties_file}" <<EOF
enable_seq_space_compaction=false
enable_unseq_space_compaction=false
enable_cross_space_compaction=false
EOF
}

reset_phase_metrics() {
    init_common_items
    numOfSe0Level_before=0
    numOfSe0Level_after=0
    numOfUnse0Level_before=0
    numOfUnse0Level_after=0
    ts_dataSize=0
    ts_numOfPoints=0
    ts_rate=0
    dataFileSize_before=0
    dataFileSize_after=0
}

collect_before_monitor_metrics() {
    collect_monitor_snapshot "${TEST_IP}" "$(date +%s)"
    dataFileSize_before="${dataFileSize}"
    numOfSe0Level_before="${numOfSe0Level}"
    numOfUnse0Level_before="${numOfUnse0Level}"
}

collect_after_monitor_metrics() {
    collect_monitor_window_data "${TEST_IP}" "${m_start_time}" "${m_end_time}"
    dataFileSize_after="${dataFileSize}"
    numOfSe0Level_after="${numOfSe0Level}"
    numOfUnse0Level_after="${numOfUnse0Level}"
}

stop_active_operation() {
    if [ "${operation_pid}" -gt 0 ] 2>/dev/null; then
        if kill -0 "${operation_pid}" 2>/dev/null; then
            kill "${operation_pid}" 2>/dev/null || true
            sleep 1
            kill -9 "${operation_pid}" 2>/dev/null || true
        fi
        wait "${operation_pid}" 2>/dev/null || true
    fi

    operation_pid=0
}

cleanup_processes() {
    stop_active_operation
    check_iotdb_pid
}

append_export_properties() {
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"

    [ -f "${properties_file}" ] || die "缺少配置文件: ${properties_file}"
    cat >> "${properties_file}" <<EOF
max_deduplicated_path_num=60000000
query_timeout_threshold=60000000
EOF
}

prepare_tablemode_schema() {
    local import_schema_tool="${TEST_IOTDB_PATH}/tools/schema/import-schema.sh"

    [ -f "${TABLEMODE_SCHEMA_FILE}" ] || {
        log "缺少 tablemode 表结构文件: ${TABLEMODE_SCHEMA_FILE}"
        return 1
    }
    [ -f "${import_schema_tool}" ] || {
        log "缺少表结构导入工具: ${import_schema_tool}"
        return 1
    }

    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" -sql_dialect table -e "create database ${TABLEMODE_DATABASE}" >/dev/null 2>&1 || return 1
    "${import_schema_tool}" -sql_dialect table -s "${TABLEMODE_SCHEMA_FILE}" -db "${TABLEMODE_DATABASE}" >/dev/null 2>&1 || return 1
}

prepare_export_output_dir() {
    safe_rm "${EXPORT_DATA_DIR}"
    mkdir -p "${EXPORT_SEQUENCE_DIR}"
}

archive_phase_log() {
    local phase="$1"
    local archive_file="${LIVE_LOG_DIR}/log.${phase}"

    if [ -f "${LIVE_LOG_FILE}" ]; then
        safe_rm "${archive_file}"
        mv "${LIVE_LOG_FILE}" "${archive_file}"
    fi
}

log_file_has_completion_marker() {
    local log_file="$1"

    [ -f "${log_file}" ] || return 1
    grep -Eq 'Import completely!|Export completely!|Work has been completed!' "${log_file}"
}

monitor_test_status() {
    local phase="$1"
    local start_epoch=0
    local now_epoch=0
    local elapsed=0

    start_epoch="$(datetime_to_epoch "${start_time}")"
    while true; do
        if log_file_has_completion_marker "${LIVE_LOG_FILE}"; then
            end_time="$(current_datetime)"
            cost_time=$(( $(datetime_to_epoch "${end_time}") - start_epoch ))
            log "${ts_type} ${data_type} ${phase} 已完成"
            return 0
        fi

        now_epoch="$(date +%s)"
        elapsed=$((now_epoch - start_epoch))
        if [ "${elapsed}" -ge "${MONITOR_TIMEOUT_SECONDS}" ]; then
            end_time="-1"
            cost_time=-100
            stop_active_operation
            log "${ts_type} ${data_type} ${phase} 已超时"
            return 1
        fi

        sleep "${MONITOR_POLL_INTERVAL_SECONDS}"
    done
}

query_point_count() {
    local output=""
    local point_count=""

    if [ "${ts_type}" = "tablemode" ]; then
        output="$("${TEST_IOTDB_PATH}/sbin/start-cli.sh" -sql_dialect table -h 127.0.0.1 -p 6667 -e "select count(s_0) from ${TABLEMODE_DATABASE}.${TABLEMODE_TABLE} where device_id = 'd_0'" 2>/dev/null || true)"
    else
        output="$("${TEST_IOTDB_PATH}/sbin/start-cli.sh" -h 127.0.0.1 -p 6667 -e "select count(s_0) from root.test.g_0.d_0" 2>/dev/null || true)"
    fi

    point_count="$(printf '%s\n' "${output}" | sed -n '4p' | tr -d '|' | tr -d '[:space:]')"
    if [ -z "${point_count}" ]; then
        point_count=-1
    fi

    printf '%s\n' "${point_count}"
}

launch_phase_command() {
    local phase="$1"
    local case_dataset_path="${DATASET_PATH}/${data_type}/${ts_type}"
    local query_sql="select * from root.test.g_0.d_0"
    local legacy_query_sql="select * from root.test.g_0.d_0"
    local -a cmd=()

    mkdir -p "${LIVE_LOG_DIR}"
    operation_pid=0

    case "${phase}" in
        load-tsfile)
            if [ ! -d "${case_dataset_path}" ]; then
                log "缺少数据集目录: ${case_dataset_path}"
                return 1
            fi

            if [ ! -f "${TEST_IOTDB_PATH}/tools/import-data.sh" ]; then
                cmd=(
                    "${TEST_IOTDB_PATH}/tools/load-tsfile.sh"
                    -s "${case_dataset_path}"
                    -h 127.0.0.1
                    -p 6667
                    -os none
                    -of none
                )
            elif [ "${ts_type}" = "tablemode" ]; then
                cmd=(
                    "${TEST_IOTDB_PATH}/tools/import-data.sh"
                    -ft tsfile
                    -sql_dialect table
                    -db "${TABLEMODE_DATABASE}"
                    -s "${case_dataset_path}"
                    -h 127.0.0.1
                    -p 6667
                    -os none
                    -of none
                )
            else
                cmd=(
                    "${TEST_IOTDB_PATH}/tools/import-data.sh"
                    -ft tsfile
                    -s "${case_dataset_path}"
                    -h 127.0.0.1
                    -p 6667
                    -os none
                    -of none
                )
            fi
            ;;
        export-tsfile)
            prepare_export_output_dir
            if [ "${ts_type}" = "tablemode" ]; then
                query_sql="select * from ${TABLEMODE_TABLE} where device_id = 'd_0'"
            fi

            if [ ! -f "${TEST_IOTDB_PATH}/tools/export-data.sh" ]; then
                cmd=(
                    "${TEST_IOTDB_PATH}/tools/export-tsfile.sh"
                    -h 127.0.0.1
                    -p 6667
                    -t "${EXPORT_SEQUENCE_DIR}"
                    -q "${legacy_query_sql}"
                )
            elif [ "${ts_type}" = "tablemode" ]; then
                cmd=(
                    "${TEST_IOTDB_PATH}/tools/export-data.sh"
                    -ft tsfile
                    -sql_dialect table
                    -db "${TABLEMODE_DATABASE}"
                    -table "${TABLEMODE_TABLE}"
                    -h 127.0.0.1
                    -p 6667
                    -t "${EXPORT_SEQUENCE_DIR}"
                    -q "${query_sql}"
                )
            else
                cmd=(
                    "${TEST_IOTDB_PATH}/tools/export-data.sh"
                    -h 127.0.0.1
                    -p 6667
                    -t "${EXPORT_SEQUENCE_DIR}"
                    -ft tsfile
                    -q "${query_sql}"
                )
            fi
            ;;
        export-csv)
            prepare_export_output_dir
            if [ "${ts_type}" = "tablemode" ]; then
                query_sql="select * from ${TABLEMODE_TABLE} where device_id = 'd_0'"
            fi

            if [ ! -f "${TEST_IOTDB_PATH}/tools/export-data.sh" ]; then
                cmd=(
                    "${TEST_IOTDB_PATH}/tools/export-csv.sh"
                    -h 127.0.0.1
                    -p 6667
                    -t "${EXPORT_SEQUENCE_DIR}"
                    -f export_csv
                    -q "${legacy_query_sql}"
                )
            elif [ "${ts_type}" = "tablemode" ]; then
                cmd=(
                    "${TEST_IOTDB_PATH}/tools/export-data.sh"
                    -ft csv
                    -sql_dialect table
                    -db "${TABLEMODE_DATABASE}"
                    -table "${TABLEMODE_TABLE}"
                    -h 127.0.0.1
                    -p 6667
                    -t "${EXPORT_SEQUENCE_DIR}"
                    -q "${query_sql}"
                )
            else
                cmd=(
                    "${TEST_IOTDB_PATH}/tools/export-data.sh"
                    -h 127.0.0.1
                    -p 6667
                    -t "${EXPORT_SEQUENCE_DIR}"
                    -ft csv
                    -q "${query_sql}"
                )
            fi
            ;;
        *)
            log "不支持的阶段: ${phase}"
            return 1
            ;;
    esac

    [ -f "${cmd[0]}" ] || {
        log "缺少操作工具: ${cmd[0]}"
        return 1
    }

    : > "${LIVE_LOG_FILE}"
    "${cmd[@]}" > "${LIVE_LOG_FILE}" 2>&1 &
    operation_pid=$!
}

insert_result_row() {
    local remark="$1"
    local insert_sql=""

    insert_sql=$(cat <<EOF
insert into ${TABLENAME} (
    commit_date_time,test_date_time,commit_id,author,ts_type,data_type,cost_time,
    numOfSe0Level_before,numOfSe0Level_after,numOfUnse0Level_before,numOfUnse0Level_after,
    ts_dataSize,ts_numOfPoints,ts_rate,start_time,end_time,dataFileSize_before,dataFileSize_after,
    maxNumofOpenFiles,maxNumofThread,errorLogSize,remark
) values (
    ${commit_date_time},
    ${test_date_time},
    $(sql_quote "${commit_id}"),
    $(sql_quote "${author}"),
    $(sql_quote "${ts_type}"),
    $(sql_quote "${data_type}"),
    ${cost_time},
    ${numOfSe0Level_before},
    ${numOfSe0Level_after},
    ${numOfUnse0Level_before},
    ${numOfUnse0Level_after},
    ${ts_dataSize},
    ${ts_numOfPoints},
    ${ts_rate},
    $(sql_quote "${start_time}"),
    $(sql_quote "${end_time}"),
    ${dataFileSize_before},
    ${dataFileSize_after},
    ${maxNumofOpenFiles},
    ${maxNumofThread},
    ${errorLogSize},
    $(sql_quote "${remark}")
)
EOF
)

    log "${commit_id} ${ts_type} ${data_type} ${remark}: 耗时 ${cost_time} 秒"
    mysql_exec "${insert_sql}"
}

run_phase() {
    local phase="$1"
    local needs_export_properties="$2"
    local phase_failed=0

    reset_phase_metrics

    if [ "${needs_export_properties}" = "1" ] && [ "${export_properties_applied}" -eq 0 ]; then
        append_export_properties
        export_properties_applied=1
    fi

    start_iotdb
    sleep "${STARTUP_GRACE_SECONDS}"
    if ! wait_for_iotdb_ready; then
        end_time="$(current_datetime)"
        cost_time=-3
        ts_numOfPoints=-1
        insert_result_row "${phase}"
        stop_iotdb
        sleep "${STOP_WAIT_SECONDS}"
        cleanup_processes
        archive_phase_log "${phase}"
        return 1
    fi

    if [ "${phase}" = "load-tsfile" ] && [ "${ts_type}" = "tablemode" ]; then
        if ! prepare_tablemode_schema; then
            end_time="$(current_datetime)"
            cost_time=-5
            ts_numOfPoints=-1
            insert_result_row "${phase}"
            stop_iotdb
            sleep "${STOP_WAIT_SECONDS}"
            cleanup_processes
            archive_phase_log "${phase}"
            return 1
        fi
    fi

    sleep "${OPERATION_WARMUP_SECONDS}"
    collect_before_monitor_metrics
    start_time="$(current_datetime)"
    m_start_time="$(date +%s)"
    if ! launch_phase_command "${phase}"; then
        end_time="$(current_datetime)"
        cost_time=-2
        ts_numOfPoints=-1
        insert_result_row "${phase}"
        stop_iotdb
        sleep "${STOP_WAIT_SECONDS}"
        cleanup_processes
        archive_phase_log "${phase}"
        return 1
    fi

    if ! monitor_test_status "${phase}"; then
        phase_failed=1
    fi

    m_end_time="$(date +%s)"
    ts_numOfPoints="$(query_point_count)"
    collect_after_monitor_metrics
    stop_iotdb
    sleep "${STOP_WAIT_SECONDS}"
    cleanup_processes

    insert_result_row "${phase}"
    archive_phase_log "${phase}"

    return "${phase_failed}"
}

backup_test_data() {
    local current_ts_type="$1"
    local current_data_type="$2"
    local protocol_code="$3"
    local backup_parent="${BACKUP_PATH}/${current_ts_type}_${current_data_type}"
    local backup_dir="${backup_parent}/${commit_date_time}_${commit_id}_${protocol_code}"

    [ -d "${TEST_IOTDB_PATH}" ] || return 0

    sudo_safe_rm "${backup_dir}"
    path_is_safe "${backup_parent}" || die "拒绝使用非预期备份路径: ${backup_parent}"
    sudo mkdir -p -- "${backup_parent}"
    path_is_safe "${backup_dir}" || die "拒绝使用非预期备份路径: ${backup_dir}"
    sudo mkdir -p -- "${backup_dir}"

    sudo_safe_rm "${TEST_IOTDB_PATH}/data"
    sudo_safe_rm "${TEST_IOTDB_PATH}/tools/data"
    path_is_safe "${TEST_IOTDB_PATH}" || die "拒绝移动非预期路径: ${TEST_IOTDB_PATH}"
    sudo mv "${TEST_IOTDB_PATH}" "${backup_dir}"
}

test_operation() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local current_data_type="$3"
    local case_failed=0

    ts_type="${current_ts_type}"
    data_type="${current_data_type}"
    export_properties_applied=0

    log "开始执行协议 ${protocol_code}、时间序列类型 ${ts_type}、数据类型 ${data_type} 的测试"
    cleanup_processes
    set_env
    mkdir -p "${LIVE_LOG_DIR}"
    modify_iotdb_config

    if ! set_protocol_class "${protocol_code}"; then
        log "协议配置无效: ${protocol_code}"
        return 1
    fi

    if ! run_phase "load-tsfile" 0; then
        case_failed=1
    fi
    if ! run_phase "export-tsfile" 1; then
        case_failed=1
    fi
    if ! run_phase "export-csv" 1; then
        case_failed=1
    fi

    backup_test_data "${ts_type}" "${data_type}" "${protocol_code}"
    return "${case_failed}"
}

main() {
    local protocol=""
    local case_item=""
    local case_ts_type=""
    local case_data_type=""
    local task_failed=0

    trap restore_test_type_file EXIT

    ensure_runtime_dependencies
    check_password

    mark_test_in_progress
    if ! fetch_next_commit; then
        sleep 60
        return 0
    fi

    update_task_status "ontesting"
    log "当前版本 ${commit_id} 未执行过测试，开始 ts_performance 测试流程"

    test_date_time="$(date +%Y%m%d%H%M%S)"
    for protocol in "${PROTOCOL_LIST[@]}"; do
        for case_item in "${TEST_CASES[@]}"; do
            IFS=':' read -r case_ts_type case_data_type <<< "${case_item}"
            if ! test_operation "${protocol}" "${case_ts_type}" "${case_data_type}"; then
                task_failed=1
            fi
        done
    done

    log "本轮 ts_performance 测试 ${test_date_time} 已结束"
    if [ "${task_failed}" -eq 0 ]; then
        update_task_status "done"
        mark_older_commits_skip
    else
        update_task_status "RError"
    fi
}

main "$@"
