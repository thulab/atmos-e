#!/usr/bin/env bash
# 场景名称：windows_test 单机 Linux 综合性能测试
# 测试目的：覆盖常规写入和查询用例，快速发现基础功能和性能回归。
# 具体步骤：
# 步骤一：选择待测 IoTDB 版本并同步 benchmark 工具。
# 步骤二：部署 IoTDB，按协议和用例配置启动服务。
# 步骤三：执行写入用例并刷新数据。
# 步骤四：执行查询用例并采集 benchmark 结果。
# 步骤五：汇总结果和监控指标，回写数据库并备份测试现场。
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="${WINDOWS_TEST_MONITOR_IP:-172.20.31.32}"
readonly TEST_TYPE="windows_test"
readonly SCENARIO_ID="windows_test"
readonly TASK_TEST_TYPE="windows_test"
readonly SCENARIO_FAILURE_POLICY="continue_and_fail"
readonly -a SCENARIO_CASE_DIMENSIONS=("protocol=223")
readonly IOTDB_PW="TimechoDB@2021"
readonly RESULT_TABLE_NAME="test_result_${TEST_TYPE}"
readonly MONITOR_TIMEOUT_SECONDS=86400
readonly BENCHMARK_WARMUP_SECONDS=10
readonly QUERY_STARTUP_EXTRA_WAIT_SECONDS=20
readonly MONITOR_DISK_ID="vdc"

readonly -a PROTOCOL_LIST=(223)
readonly -a INSERT_CONFIGS=(seq_w unseq_w seq_rw unseq_rw)
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/../../common" && pwd)"
# shellcheck source=script/common/runtime_common.sh
source "${COMMON_DIR}/runtime_common.sh"

# 将 Windows 测试场景属性追加到 IoTDB 配置。
append_iotdb_properties() {
    local properties_file="$1"

    cat >> "${properties_file}" <<EOF
enable_seq_space_compaction=false
enable_unseq_space_compaction=false
enable_cross_space_compaction=false
query_timeout_threshold=60000000
EOF
}

op_type=""
current_protocol_code=""
query_id=""
query_label_name=""
query_suite_type=""
query_sensor_type=""
query_repeat_no=""
result_kind=""
# 初始化 Windows 测试用例、查询列表及运行参数。
init_items() {
    init_common_items
    query_id=""
    query_label_name=""
    query_suite_type=""
    query_sensor_type=""
    query_repeat_no=""
    result_kind=""
    maxCPULoad=0
    avgCPULoad=0
    maxDiskIOOpsRead=0
    maxDiskIOOpsWrite=0
    maxDiskIOSizeRead=0
    maxDiskIOSizeWrite=0
}

# 将 IoTDB root 用户密码设置为测试所需密码。
change_root_password() {
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" -e "ALTER USER root SET PASSWORD '${IOTDB_PW}'" >/dev/null 2>&1
}

# 执行 IoTDB flush，确保写入数据可供后续查询。
flush_iotdb() {
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" -u root -pw "${IOTDB_PW}" -h 127.0.0.1 -p 6667 -e "flush" >/dev/null 2>&1
}

# 根据用例名称解析对应的配置文件路径。
resolve_config_source() {
    local config_name="$1"
    local config_root="${ATMOS_PATH}/conf/${TEST_TYPE}"
    local resolved_path=""

    resolved_path="$(resolve_config_from_roots "${config_name}" "${config_root}/query" "${config_root}")" || \
        die "缺少 benchmark 配置文件: ${config_name}"
    printf '%s\n' "${resolved_path}"
}

# 将 Windows 场景配置复制到 IoTDB 或 Benchmark 目录。
copy_windows_config() {
    local config_name="$1"

    copy_benchmark_config "$(resolve_config_source "${config_name}")"
}

# 收集当前 Windows 测试用例的监控指标。
collect_monitor_data() {
    collect_resource_monitor_data "${TEST_IP}" "${MONITOR_DISK_ID}" "${m_start_time}" "${m_end_time}"
}

# 兼容旧版 Windows 测试的备份函数调用参数。
legacy_backup_test_data_compat() {
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

# 备份 Windows 测试数据、配置和运行日志。
backup_test_data() {
    local current_insert_type="$1"
    local backup_dir=""

    backup_dir="$(build_scoped_path \
        "${BACKUP_PATH}" \
        "protocol=${current_protocol_code}" \
        "case=${current_insert_type}" \
        "commit=${commit_date_time}_${commit_id}")"
    archive_test_runtime_artifacts "${backup_dir}"
}

# 准备写入结果记录所需的上下文及字段值。
prepare_ingestion_result_context() {
    query_id=""
    query_label_name=""
    query_suite_type=""
    query_sensor_type=""
    query_repeat_no=""
    result_kind="ingestion"
}

# 准备查询结果记录所需的上下文及字段值。
prepare_query_result_context() {
    local current_query="$1"
    local current_query_label="$2"

    query_id="$(normalize_query_name "${current_query}")"
    query_label_name="${current_query_label}"
    query_suite_type="${data_type}"
    query_sensor_type=""
    query_repeat_no="1"
    result_kind="query"
}

# 将 Windows 测试用例的结果写入数据库。
insert_result_row() {
    local query_repeat_value="NULL"
    local insert_sql=""

    if [ -n "${query_repeat_no}" ]; then
        query_repeat_value="${query_repeat_no}"
    fi

    insert_sql=$(cat <<EOF
insert into ${RESULT_TABLE_NAME} (
    commit_date_time,test_date_time,commit_id,author,ts_type,data_type,op_type,okPoint,okOperation,failPoint,
    failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,
    end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,errorLogSize,walFileSize,
    remark
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
    $(sql_quote "${current_protocol_code}")
)
EOF
)

    mysql_exec "${insert_sql}"
}

# 构造并持久化当前失败用例的结果记录。
record_failure_result() {
    local failure_code="$1"

    [ -n "${end_time}" ] || end_time="$(current_datetime)"
    cost_time="${failure_code}"
    throughput="${failure_code}"
    insert_result_row
}

# 执行指定的 Benchmark 写入或性能用例。
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

# 执行单条查询用例并记录结果与监控数据。
run_query_case() {
    local current_query="$1"
    local query_label="$2"
    local query_failed=0

    init_items
    ts_type="common"
    prepare_query_result_context "${current_query}" "${query_label}"
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

    copy_windows_config "${current_query}"
    if ! run_benchmark_case "${current_query}" "${query_label}" query 0; then
        query_failed=1
    fi

    stop_iotdb
    sleep "${BENCHMARK_STOP_WAIT_SECONDS}"
    cleanup_processes
    return "${query_failed}"
}

# 执行单条写入用例并刷新数据供查询套件使用。
run_insert_case() {
    local current_insert_type="$1"
    local query_index=0
    local case_failed=0

    init_items
    ts_type="common"
    data_type="${current_insert_type}"
    op_type="INGESTION"
    prepare_ingestion_result_context

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
    copy_windows_config "${current_insert_type}"
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

    if [[ "${data_type}" == "seq_w" || "${data_type}" == "unseq_w" ]]; then
        for ((query_index = 0; query_index < ${#QUERY_LIST[@]}; query_index++)); do
            if ! run_query_case "${QUERY_LIST[${query_index}]}" "${QUERY_LABELS[${query_index}]}"; then
                case_failed=1
            fi
        done
    fi

    [ -d "${TEST_IOTDB_PATH}" ] && backup_test_data "${current_insert_type}"
    return "${case_failed}"
}

# 按协议执行完整 Windows 场景用例并汇总失败状态。
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

# 执行 Windows 测试脚本的命令行主流程。
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
    log "当前版本 ${commit_id} 未执行过测试，开始 windows_test 流程"

    test_date_time="$(date +%Y%m%d%H%M%S)"
    for protocol in "${PROTOCOL_LIST[@]}"; do
        if ! test_operation "${protocol}"; then
            task_failed=1
        fi
    done

    log "本轮 windows_test ${test_date_time} 已结束"
    if [ "${task_failed}" -eq 0 ]; then
        update_task_status "done"
        mark_older_commits_skip
    else
        update_task_status "RError"
    fi
}

# 准备测试环境、检查配置并注册退出时的状态恢复。
scenario_task_prepare() { trap restore_test_type_file EXIT; ensure_runtime_dependencies; check_password; [ "${#QUERY_LIST[@]}" -eq "${#QUERY_LABELS[@]}" ] || return 20; if [ "${ENABLE_BENCHMARK_VERSION_CHECK}" = "1" ]; then check_benchmark_version; fi; mark_test_in_progress; }
# 认领待测提交并记录其元数据。
scenario_task_claim() { fetch_next_commit || return 1; TASK_CTX[commit_id]="${commit_id}"; TASK_CTX[author]="${author}"; TASK_CTX[commit_date_time]="${commit_date_time}"; test_date_time="$(date +%Y%m%d%H%M%S)"; }
# 将 Windows 测试任务状态更新为运行中。
scenario_task_mark_running() { update_task_status "ontesting"; }
# 按当前协议维度执行 Windows 测试套件。
scenario_case_execute() { test_operation "${CASE_PROTOCOL}"; }
# 标记测试成功并跳过较早的待处理提交。
scenario_task_finish_success() { update_task_status "done"; mark_older_commits_skip; }
# 将 Windows 测试任务标记为失败。
scenario_task_finish_failure() { update_task_status "RError"; }
