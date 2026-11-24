#!/usr/bin/env bash
# 场景名称：TsFile 工具性能测试
# 测试目的：验证 load-tsfile、export-tsfile 和 export-csv 工具在不同数据模型下的性能。
# 具体步骤：
# 步骤一：选择待测 IoTDB 版本并准备 TsFile 数据集。
# 步骤二：部署 IoTDB，按场景配置 schema 和工具参数。
# 步骤三：执行 load-tsfile 导入阶段并采集结果。
# 步骤四：执行 export-tsfile 和 export-csv 导出阶段并采集结果。
# 步骤五：汇总各阶段指标，回写数据库并备份测试现场。
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_TYPE="ts_performance"
readonly SCENARIO_ID="ts_performance"
readonly TASK_TEST_TYPE="ts_performance"
readonly SCENARIO_FAILURE_POLICY="continue_and_fail"
readonly -a SCENARIO_CASES=(
    $'protocol=223\ttype=common\tdata_type=sequence'
    $'protocol=223\ttype=common\tdata_type=unsequence'
    $'protocol=223\ttype=aligned\tdata_type=sequence'
    $'protocol=223\ttype=aligned\tdata_type=unsequence'
    $'protocol=223\ttype=tempaligned\tdata_type=sequence'
    $'protocol=223\ttype=tempaligned\tdata_type=unsequence'
    $'protocol=223\ttype=tablemode\tdata_type=sequence'
    $'protocol=223\ttype=tablemode\tdata_type=unsequence'
)
readonly TEST_IP="172.20.31.8"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/../../common" && pwd)"
# shellcheck source=script/common/runtime_common.sh
source "${COMMON_DIR}/runtime_common.sh"

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

# 检查 TsFile 工具性能测试运行所需的命令和依赖。
ensure_runtime_dependencies() {
    ensure_base_runtime_dependencies
    require_commands find
}

# 将测试属性追加到 IoTDB 配置文件。
append_iotdb_properties() {
    local properties_file="$1"

    append_iotdb_compaction_disabled_properties "${properties_file}"
}

# 清零当前 TsFile 阶段的耗时和监控指标。
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

# 统计目录大小并转换为 GiB。
directory_size_gib() {
    local path="$1"
    local size_bytes=0

    if [ ! -d "${path}" ]; then
        printf '0\n'
        return 0
    fi

    size_bytes="$(du -sb -- "${path}" 2>/dev/null | awk 'NR == 1 { print $1 }')"
    bytes_to_gib "${size_bytes:-0}"
}

# 递归统计指定目录中的 TsFile 数量。
count_tsfiles() {
    local path="$1"

    if [ ! -d "${path}" ]; then
        printf '0\n'
        return 0
    fi

    find "${path}" -type f -name '*.tsfile' | wc -l | awk '{print $1}'
}

# 采集 TsFile 导入或导出阶段的数据文件统计。
collect_data_stats() {
    local base_path="$1"
    local stage="$2"
    local data_root="${base_path}/data"
    local total_size=0
    local seq_count=0
    local unseq_count=0

    total_size="$(directory_size_gib "${data_root}")"
    seq_count="$(count_tsfiles "${data_root}/datanode/data/sequence")"
    unseq_count="$(count_tsfiles "${data_root}/datanode/data/unsequence")"

    if [ "${stage}" = "before" ]; then
        dataFileSize_before="${total_size}"
        numOfSe0Level_before="${seq_count}"
        numOfUnse0Level_before="${unseq_count}"
    else
        dataFileSize_after="${total_size}"
        numOfSe0Level_after="${seq_count}"
        numOfUnse0Level_after="${unseq_count}"
    fi
}

# 采集当前工具阶段结束后的监控指标。
collect_after_monitor_metrics() {
    collect_monitor_window_data "${TEST_IP}" "${m_start_time}" "${m_end_time}"
}

# 终止当前仍在运行的 TsFile 工具操作。
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

# 清理 TsFile 工具性能测试遗留进程。
cleanup_processes() {
    stop_active_operation
    check_iotdb_pid
}

# 追加 TsFile 导出阶段所需的 IoTDB 配置。
append_export_properties() {
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"

    [ -f "${properties_file}" ] || die "缺少配置文件: ${properties_file}"
    cat >> "${properties_file}" <<EOF
max_deduplicated_path_num=60000000
query_timeout_threshold=60000000
EOF
}

# 为表模型性能用例准备数据库和表结构。
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

# 创建并清理指定导出阶段的输出目录。
prepare_export_output_dir() {
    sudo_safe_rm "${EXPORT_DATA_DIR}"
    mkdir -p "${EXPORT_SEQUENCE_DIR}"
}

# 归档当前阶段生成的日志文件。
archive_phase_log() {
    local phase="$1"
    local archive_file="${LIVE_LOG_DIR}/log.${phase}"

    if [ -f "${LIVE_LOG_FILE}" ]; then
        sudo_safe_rm "${archive_file}"
        mv "${LIVE_LOG_FILE}" "${archive_file}"
    fi
}

# 检查日志文件是否包含阶段完成标记。
log_file_has_completion_marker() {
    local log_file="$1"

    [ -f "${log_file}" ] || return 1
    grep -Eq 'Import completely!|Export completely!|Work has been completed!' "${log_file}"
}

# 监控工具进程并依据日志标记判断阶段完成或失败。
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

# 查询 IoTDB 中当前测试数据点数量。
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

# 启动指定 TsFile 工具阶段命令并记录运行状态。
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

# 将 TsFile 各阶段测试指标写入数据库结果表。
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

# 执行单个 TsFile 导入或导出阶段并采集结果。
run_ts_phase() {
    local phase="$1"
    local before_base="$2"
    local after_base="$3"
    local needs_export_properties="$4"
    local phase_failed=0

    reset_phase_metrics
    collect_data_stats "${before_base}" "before"

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

    collect_data_stats "${after_base}" "after"
    insert_result_row "${phase}"
    archive_phase_log "${phase}"

    return "${phase_failed}"
}

# 备份 TsFile 测试数据、工具输出和阶段日志。
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

# 按数据模型和工具阶段编排完整性能测试。
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

    if ! run_ts_phase "load-tsfile" "${DATASET_PATH}/${data_type}/${ts_type}" "${TEST_IOTDB_PATH}" 0; then
        case_failed=1
    fi
    if ! run_ts_phase "export-tsfile" "${TEST_IOTDB_PATH}" "${TEST_IOTDB_PATH}/tools" 1; then
        case_failed=1
    fi
    if ! run_ts_phase "export-csv" "${TEST_IOTDB_PATH}" "${TEST_IOTDB_PATH}/tools" 1; then
        case_failed=1
    fi

    backup_test_data "${ts_type}" "${data_type}" "${protocol_code}"
    return "${case_failed}"
}

# 执行 TsFile 工具性能脚本的命令行主流程。
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

# 准备测试运行环境并设置退出时的状态恢复操作。
scenario_task_prepare() { trap restore_test_type_file EXIT; ensure_runtime_dependencies; check_password; mark_test_in_progress; }
# 认领待测提交并准备提交对应的测试版本。
scenario_task_claim() { fetch_next_commit || return 1; TASK_CTX[commit_id]="${commit_id}"; TASK_CTX[author]="${author}"; TASK_CTX[commit_date_time]="${commit_date_time}"; test_date_time="$(date +%Y%m%d%H%M%S)"; }
# 将任务状态更新为运行中。
scenario_task_mark_running() { update_task_status "ontesting"; }
# 执行当前数据模型和阶段对应的 TsFile 测试。
scenario_case_execute() { test_operation "${CASE_PROTOCOL}" "${CASE_TYPE}" "${CASE_DATA_TYPE}"; }
# 标记测试成功并处理较早的待测提交。
scenario_task_finish_success() { update_task_status "done"; mark_older_commits_skip; }
# 将 TsFile 性能测试任务标记为失败。
scenario_task_finish_failure() { update_task_status "RError"; }
