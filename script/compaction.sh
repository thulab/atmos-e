#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="172.20.31.28"
readonly TEST_TYPE="compaction"
readonly DATA_PATH="/nasdata/compaction/DataSet"
readonly DATASET_PATH="${DATA_PATH}"
readonly -a PROTOCOL_LIST=(211)
readonly -a TS_LIST=(common aligned)
readonly STOP_WAIT_SECONDS=30
readonly COMPACTION_INITIAL_WAIT_SECONDS=30
readonly COMPACTION_IDLE_CONFIRM_SECONDS=70
readonly COMPACTION_TIMEOUT_SECONDS=7200
readonly DEFAULT_TARGET_COMPACTION_FILE_SIZE=1073741824
readonly CROSS_TARGET_COMPACTION_FILE_SIZE=2147483648
readonly SEQ_READY_RETRIES=20
readonly SEQ_READY_INTERVAL_SECONDS=30
readonly UNSEQ_READY_RETRIES=10
readonly UNSEQ_READY_INTERVAL_SECONDS=5
readonly CROSS_READY_RETRIES=20
readonly CROSS_READY_INTERVAL_SECONDS=30
readonly DEFAULT_DISK_ID_REGEX="^vdc$"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/runtime_common.sh
source "${SCRIPT_DIR}/runtime_common.sh"

readonly TABLENAME="test_result_${TEST_TYPE}"

comp_type=""
numOfSe0Level_before=0
numOfSe0Level_after=0
numOfUnse0Level_before=0
numOfUnse0Level_after=0
ts_dataSize=0
ts_numOfPoints=0
compaction_rate=0
comp_start_time="0"
comp_end_time="0"
dataFileSize_before="0"
dataFileSize_after="0"
maxCPULoad=0
avgCPULoad=0
maxDiskIOOpsRead=0
maxDiskIOOpsWrite=0
maxDiskIOSizeRead=0
maxDiskIOSizeWrite=0

ensure_runtime_dependencies() {
    ensure_base_runtime_dependencies
    require_command find
    require_command tail
}

append_iotdb_properties() {
    local properties_file="$1"

    cat >> "${properties_file}" <<EOF
series_slot_num=10000
target_compaction_file_size=${DEFAULT_TARGET_COMPACTION_FILE_SIZE}
enable_seq_space_compaction=false
enable_unseq_space_compaction=false
enable_cross_space_compaction=false
EOF
}

init_items() {
    init_common_items
    ts_type=""
    comp_type=""
    numOfSe0Level_before=0
    numOfSe0Level_after=0
    numOfUnse0Level_before=0
    numOfUnse0Level_after=0
    ts_dataSize=0
    ts_numOfPoints=0
    compaction_rate=0
    comp_start_time="0"
    comp_end_time="0"
    dataFileSize_before="0"
    dataFileSize_after="0"
    maxCPULoad=0
    avgCPULoad=0
    maxDiskIOOpsRead=0
    maxDiskIOOpsWrite=0
    maxDiskIOSizeRead=0
    maxDiskIOSizeWrite=0
}

cleanup_processes() {
    check_iotdb_pid
}

copy_dataset() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local source_path="${DATASET_PATH}/${protocol_code}/${current_ts_type}/data"

    [ -d "${source_path}" ] || die "缺少数据集目录: ${source_path}"
    cp -rf -- "${source_path}" "${TEST_IOTDB_PATH}/"
}

configure_compaction_mode() {
    local current_compaction_type="$1"
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"
    local seq_enabled="false"
    local unseq_enabled="false"
    local cross_enabled="false"
    local target_file_size="${DEFAULT_TARGET_COMPACTION_FILE_SIZE}"

    case "${current_compaction_type}" in
        seq_space)
            seq_enabled="true"
            ;;
        unseq_space)
            unseq_enabled="true"
            ;;
        cross_space)
            cross_enabled="true"
            target_file_size="${CROSS_TARGET_COMPACTION_FILE_SIZE}"
            ;;
        *)
            return 1
            ;;
    esac

    cat >> "${properties_file}" <<EOF
target_compaction_file_size=${target_file_size}
enable_seq_space_compaction=${seq_enabled}
enable_unseq_space_compaction=${unseq_enabled}
enable_cross_space_compaction=${cross_enabled}
EOF
}

wait_for_compaction_ready() {
    local retries="$1"
    local interval_seconds="$2"
    local attempt=0
    local iotdb_state=""

    for ((attempt = 1; attempt <= retries; attempt++)); do
        iotdb_state="$("${TEST_IOTDB_PATH}/sbin/start-cli.sh" -e "show cluster" 2>/dev/null | grep -F 'Total line number = 2' || true)"
        if [ "${iotdb_state}" = "Total line number = 2" ]; then
            return 0
        fi
        sleep "${interval_seconds}"
    done

    return 1
}

collect_before_monitor_metrics() {
    collect_monitor_snapshot "${TEST_IP}" "$(date +%s)"
    dataFileSize_before="${dataFileSize}"
    numOfSe0Level_before="${numOfSe0Level}"
    numOfUnse0Level_before="${numOfUnse0Level}"
}

append_timeout_compaction_log() {
    local current_compaction_type="$1"
    local log_file="${TEST_IOTDB_PATH}/logs/log_datanode_compaction.log"
    local timestamp=""

    mkdir -p "${log_file%/*}"
    timestamp="$(date '+%Y-%m-%d %H:%M:%S,000')"

    case "${current_compaction_type}" in
        cross_space)
            printf '%s [pool-21-IoTDB-Compaction-1] INFO  o.a.i.d.e.c.c.CrossSpaceCompactionTask:207 - root.test.g_0-1 [Compaction] CrossSpaceCompaction task finishes successfully, time cost is -1 s, compaction speed is 0 MB/s\n' "${timestamp}" >> "${log_file}"
            ;;
        *)
            printf '%s [pool-21-IoTDB-Compaction-1] INFO  o.a.i.d.e.c.i.InnerSpaceCompactionTask:239 - root.test.g_0-1 [Compaction] InnerSpaceCompaction task finishes successfully, target file is timeout.tsfile, time cost is -1 s, compaction speed is 0 MB/s\n' "${timestamp}" >> "${log_file}"
            ;;
    esac
}

monitor_compaction_completion() {
    local current_compaction_type="$1"
    local data_dir="${TEST_IOTDB_PATH}/data/datanode/data"
    local log_file="${TEST_IOTDB_PATH}/logs/log_datanode_compaction.log"
    local now_epoch=0
    local elapsed=0
    local active_count=0

    while true; do
        if [ -d "${data_dir}" ]; then
            active_count="$(find "${data_dir}" -name "*compaction.log" | wc -l)"
        else
            active_count=0
        fi

        if [ "${active_count}" -le 0 ] && [ -f "${log_file}" ]; then
            sleep "${COMPACTION_IDLE_CONFIRM_SECONDS}"
            if [ -d "${data_dir}" ]; then
                active_count="$(find "${data_dir}" -name "*compaction.log" | wc -l)"
            else
                active_count=0
            fi

            if [ "${active_count}" -le 0 ] && [ -f "${log_file}" ]; then
                log "${current_compaction_type} 压实完成"
                return 0
            fi
        fi

        now_epoch="$(date +%s)"
        elapsed=$((now_epoch - m_start_time))
        if [ "${elapsed}" -ge "${COMPACTION_TIMEOUT_SECONDS}" ]; then
            log "${current_compaction_type} 压实超时，写入兜底日志"
            append_timeout_compaction_log "${current_compaction_type}"
            return 1
        fi

        sleep "${MONITOR_POLL_INTERVAL_SECONDS}"
    done
}

parse_compaction_log() {
    local log_file="${TEST_IOTDB_PATH}/logs/log_datanode_compaction.log"
    local line=""

    [ -f "${log_file}" ] || return 1

    comp_start_time="$(awk 'NR == 1 { print substr($1 " " $2, 1, 19); exit }' "${log_file}")"
    comp_end_time="$(awk 'END { print substr($1 " " $2, 1, 19) }' "${log_file}")"
    line="$(grep -E 'InnerSpaceCompaction task finishes successfully|CrossSpaceCompaction task finishes successfully' "${log_file}" | tail -n 1 || true)"
    [ -n "${line}" ] || return 1

    cost_time="$(printf '%s\n' "${line}" | sed -n 's/.*time cost is \([-0-9.]\+\) s.*/\1/p')"
    [ -n "${cost_time}" ] || return 1
    [ -n "${comp_start_time}" ] || return 1
    [ -n "${comp_end_time}" ] || return 1
}

collect_data_after() {
    compaction_rate=0
    ts_dataSize=0
    ts_numOfPoints=0

    if ! parse_compaction_log; then
        cost_time=-2
        comp_start_time="0"
        comp_end_time="0"
        return 1
    fi
}

collect_monitor_metrics() {
    collect_resource_monitor_data "${TEST_IP}" "${DEFAULT_DISK_ID_REGEX}" "${m_start_time}" "${m_end_time}"
    dataFileSize_after="${dataFileSize}"
    numOfSe0Level_after="${numOfSe0Level}"
    numOfUnse0Level_after="${numOfUnse0Level}"
    if [ "${errorLogSize:-0}" -gt 0 ]; then
        errorLogSize=1
    else
        errorLogSize=0
    fi
}

insert_result_row() {
    local protocol_code="$1"
    local insert_sql=""

    insert_sql=$(cat <<EOF
insert into ${TABLENAME} (
    commit_date_time,test_date_time,commit_id,author,ts_type,comp_type,cost_time,
    numOfSe0Level_before,numOfSe0Level_after,numOfUnse0Level_before,numOfUnse0Level_after,
    ts_dataSize,ts_numOfPoints,compaction_rate,comp_start_time,comp_end_time,
    dataFileSize_before,dataFileSize_after,maxNumofOpenFiles,maxNumofThread,errorLogSize,
    avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,remark
) values (
    ${commit_date_time},
    ${test_date_time},
    $(sql_quote "${commit_id}"),
    $(sql_quote "${author}"),
    $(sql_quote "${ts_type}"),
    $(sql_quote "${comp_type}"),
    ${cost_time},
    ${numOfSe0Level_before},
    ${numOfSe0Level_after},
    ${numOfUnse0Level_before},
    ${numOfUnse0Level_after},
    ${ts_dataSize},
    ${ts_numOfPoints},
    ${compaction_rate},
    $(sql_quote "${comp_start_time}"),
    $(sql_quote "${comp_end_time}"),
    $(sql_quote "${dataFileSize_before}"),
    $(sql_quote "${dataFileSize_after}"),
    ${maxNumofOpenFiles},
    ${maxNumofThread},
    ${errorLogSize},
    ${avgCPULoad},
    ${maxCPULoad},
    ${maxDiskIOSizeRead},
    ${maxDiskIOSizeWrite},
    ${maxDiskIOOpsRead},
    ${maxDiskIOOpsWrite},
    $(sql_quote "${protocol_code}")
)
EOF
)

    mysql_exec "${insert_sql}"
    log "${ts_type} ${comp_type} 压实耗时 ${cost_time} 秒"
}

archive_compaction_artifacts() {
    local current_compaction_type="$1"
    local logs_dir="${TEST_IOTDB_PATH}/logs"
    local target_dir="${TEST_IOTDB_PATH}/${current_compaction_type}"

    [ -d "${logs_dir}" ] || return 0

    safe_rm "${target_dir}"
    mkdir -p "${target_dir}"
    copy_if_exists "${TEST_IOTDB_PATH}/conf" "${target_dir}/" "conf"
    mv "${logs_dir}" "${target_dir}/"
}

backup_test_data() {
    local current_ts_type="$1"
    local protocol_code="$2"
    local backup_parent="${BACKUP_PATH}/${current_ts_type}"
    local backup_dir="${backup_parent}/${commit_date_time}_${commit_id}_${protocol_code}"

    sudo_safe_rm "${backup_dir}"
    path_is_safe "${backup_parent}" || die "拒绝使用非预期备份路径: ${backup_parent}"
    sudo mkdir -p -- "${backup_parent}"
    path_is_safe "${backup_dir}" || die "拒绝使用非预期备份路径: ${backup_dir}"
    sudo mkdir -p -- "${backup_dir}"

    sudo_safe_rm "${TEST_IOTDB_PATH}/data"
    path_is_safe "${TEST_IOTDB_PATH}" || die "拒绝移动非预期路径: ${TEST_IOTDB_PATH}"
    sudo mv "${TEST_IOTDB_PATH}" "${backup_dir}"
}

record_startup_failure() {
    local protocol_code="$1"

    cost_time=-3
    comp_start_time="0"
    comp_end_time="0"
    insert_result_row "${protocol_code}"
}

run_compaction_case() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local current_compaction_type="$3"
    local ready_retries=0
    local ready_interval_seconds=0
    local case_failed=0

    init_items
    ts_type="${current_ts_type}"
    comp_type="${current_compaction_type}"

    case "${current_compaction_type}" in
        seq_space)
            ready_retries="${SEQ_READY_RETRIES}"
            ready_interval_seconds="${SEQ_READY_INTERVAL_SECONDS}"
            ;;
        unseq_space)
            ready_retries="${UNSEQ_READY_RETRIES}"
            ready_interval_seconds="${UNSEQ_READY_INTERVAL_SECONDS}"
            ;;
        cross_space)
            ready_retries="${CROSS_READY_RETRIES}"
            ready_interval_seconds="${CROSS_READY_INTERVAL_SECONDS}"
            ;;
        *)
            die "不支持的压实类型: ${current_compaction_type}"
            ;;
    esac

    configure_compaction_mode "${current_compaction_type}" || die "压实配置失败: ${current_compaction_type}"
    start_iotdb
    sleep "${STARTUP_GRACE_SECONDS}"

    if ! wait_for_compaction_ready "${ready_retries}" "${ready_interval_seconds}"; then
        log "${current_compaction_type} 启动失败，记录失败结果"
        record_startup_failure "${protocol_code}"
        stop_iotdb
        sleep "${STOP_WAIT_SECONDS}"
        cleanup_processes
        return 1
    fi

    collect_before_monitor_metrics
    m_start_time="$(date +%s)"
    sleep "${COMPACTION_INITIAL_WAIT_SECONDS}"
    if ! monitor_compaction_completion "${current_compaction_type}"; then
        case_failed=1
    fi

    m_end_time="$(date +%s)"
    collect_monitor_metrics
    stop_iotdb
    sleep "${STOP_WAIT_SECONDS}"
    cleanup_processes
    if ! collect_data_after; then
        log "${current_compaction_type} 压实日志解析失败"
        case_failed=1
    fi
    insert_result_row "${protocol_code}"
    archive_compaction_artifacts "${current_compaction_type}"

    return "${case_failed}"
}

test_operation() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local compaction_case=""
    local operation_failed=0

    log "开始执行协议 ${protocol_code}、时序类型 ${current_ts_type} 的压实流程"
    cleanup_processes
    set_env
    modify_iotdb_config
    if ! set_protocol_class "${protocol_code}"; then
        log "协议配置无效: ${protocol_code}"
        return 1
    fi
    copy_dataset "${protocol_code}" "${current_ts_type}"

    for compaction_case in seq_space unseq_space cross_space; do
        if ! run_compaction_case "${protocol_code}" "${current_ts_type}" "${compaction_case}"; then
            operation_failed=1
        fi
    done

    [ -d "${TEST_IOTDB_PATH}" ] && backup_test_data "${current_ts_type}" "${protocol_code}"
    return "${operation_failed}"
}

main() {
    local protocol=""
    local ts=""
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
    log "当前版本 ${commit_id} 未执行过测试，开始 compaction 流程"

    test_date_time="$(date +%Y%m%d%H%M%S)"
    for protocol in "${PROTOCOL_LIST[@]}"; do
        for ts in "${TS_LIST[@]}"; do
            if ! test_operation "${protocol}" "${ts}"; then
                task_failed=1
            fi
        done
    done

    log "本轮 compaction 测试 ${test_date_time} 已结束"
    if [ "${task_failed}" -eq 0 ]; then
        update_task_status "done"
        mark_older_commits_skip
    else
        update_task_status "RError"
    fi
}

main "$@"
