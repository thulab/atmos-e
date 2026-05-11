#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_TYPE="sql_coverage"

readonly INIT_PATH="/root/zk_test"
readonly ATMOS_PATH="${INIT_PATH}/atmos-e"
readonly TOOL_PATH="${INIT_PATH}/iotdb-sql-test"
readonly TESTCASE_PATH="${INIT_PATH}/iotdb-sql-testcase"
readonly REPOS_PATH="/nasdata/repository/master"
readonly BACKUP_PATH="/nasdata/repository/${TEST_TYPE}/master"

readonly TEST_INIT_PATH="/data/qa"
readonly TEST_IOTDB_PATH="${TEST_INIT_PATH}/apache-iotdb"
readonly TEST_TOOL_PATH="${TEST_INIT_PATH}/iotdb-sql-test"
readonly NGINX_DATA_PATH="/data/nginx"
readonly TSFILE_DATA_PATH="/data/tsfile"

readonly MYSQLHOSTNAME="111.200.37.158"
readonly PORT="13306"
readonly USERNAME="iotdbatm"
readonly PASSWORD="${ATMOS_DB_PASSWORD:-}"
readonly DBNAME="QA_ATM"
readonly TABLENAME="test_result_${TEST_TYPE}"
readonly TASK_TABLENAME="commit_history"

readonly -a PROTOCOL_CLASS=(
    ""
    "org.apache.iotdb.consensus.simple.SimpleConsensus"
    "org.apache.iotdb.consensus.ratis.RatisConsensus"
    "org.apache.iotdb.consensus.iot.IoTConsensus"
    "org.apache.iotdb.consensus.iot.IoTConsensusV2"
)
readonly PROTOCOL_CODE="223"
readonly -a MODE_LIST=(treemode tablemode)

readonly IOTDB_READY_RETRIES=10
readonly IOTDB_READY_INTERVAL_SECONDS=5
readonly STARTUP_GRACE_SECONDS=10
readonly TREE_STARTUP_WAIT_SECONDS=60
readonly TABLE_STARTUP_WAIT_SECONDS=30
readonly RESULT_TIMEOUT_SECONDS=7200
readonly RESULT_POLL_INTERVAL_SECONDS=10
readonly SHUTDOWN_WAIT_SECONDS=30
readonly TESTCASE_PULL_TIMEOUT_SECONDS=100

readonly FIRST_INSERT_REMARK="FirstInsertSQL"
readonly TREE_REMARK="treemode"
readonly TABLE_REMARK="tablemode"
readonly FIRST_INSERT_SQL="insert into root.ln.wf02.wt02(timestamp, status, hardware) VALUES (3, false, 'v3'),(4, true, 'v4')"
readonly RESET_TREE_SQL="drop database root.**"

commit_id=""
author=""
commit_date_time=""
test_date_time=""
start_time=""
end_time=""
cost_time=0
active_test_pid=0

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    log "错误: $*"
    exit 1
}

trim() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

current_datetime() {
    date '+%Y-%m-%d %H:%M:%S'
}

current_millis() {
    date +%s%3N
}

datetime_to_epoch() {
    date -d "$1" +%s
}

normalize_datetime() {
    printf '%s' "$1" | tr -cd '0-9'
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "缺少依赖命令: $1"
}

require_directory() {
    local path="$1"
    local label="$2"
    [ -d "${path}" ] || die "缺少目录 ${label}: ${path}"
}

require_file() {
    local path="$1"
    local label="$2"
    [ -f "${path}" ] || die "缺少文件 ${label}: ${path}"
}

check_password() {
    if [ -z "${PASSWORD}" ]; then
        die "ATMOS_DB_PASSWORD 未设置，无法连接 MySQL"
    fi
}

ensure_runtime_dependencies() {
    local cmd=""
    for cmd in awk cp date find git grep jps kill mkdir mv mysql rm sed sudo timeout tr wc; do
        require_command "${cmd}"
    done
}

path_is_safe() {
    local path="$1"
    [ -n "${path}" ] || return 1

    case "${path}" in
        "/"|"/data"|"/data/qa"|"/nasdata"|".")
            return 1
            ;;
        "${INIT_PATH}"/*|"${TEST_INIT_PATH}"/*|"${BACKUP_PATH}"/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

safe_rm() {
    local path="$1"
    [ -e "${path}" ] || return 0
    path_is_safe "${path}" || die "拒绝删除非预期路径: ${path}"
    rm -rf -- "${path}"
}

sudo_safe_rm() {
    local path="$1"
    [ -e "${path}" ] || return 0
    path_is_safe "${path}" || die "拒绝删除非预期路径: ${path}"
    sudo rm -rf -- "${path}"
}

clear_directory_contents() {
    local path="$1"

    case "${path}" in
        "${NGINX_DATA_PATH}"|"${TSFILE_DATA_PATH}")
            ;;
        *)
            die "拒绝清理非预期共享目录: ${path}"
            ;;
    esac

    mkdir -p "${path}"
    find "${path}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

copy_if_exists() {
    local source="$1"
    local target="$2"
    local label="${3:-$1}"

    if [ ! -e "${source}" ]; then
        log "跳过复制，缺少 ${label}: ${source}"
        return 0
    fi

    cp -rf -- "${source}" "${target}"
}

copy_required_dir_contents() {
    local source_dir="$1"
    local target_dir="$2"
    local label="$3"

    require_directory "${source_dir}" "${label}"
    mkdir -p "${target_dir}"
    cp -rf -- "${source_dir}/." "${target_dir}/"
}

copy_required_path() {
    local source_path="$1"
    local target_path="$2"
    local label="$3"

    [ -e "${source_path}" ] || die "缺少 ${label}: ${source_path}"
    cp -rf -- "${source_path}" "${target_path}"
}

mysql_exec() {
    local sql="$1"
    MYSQL_PWD="${PASSWORD}" mysql -N -B -h"${MYSQLHOSTNAME}" -P"${PORT}" -u"${USERNAME}" "${DBNAME}" -e "${sql}"
}

sql_quote() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="$(printf '%s' "${value}" | sed "s/'/''/g")"
    printf "'%s'" "${value}"
}

update_task_status() {
    local status="$1"
    mysql_exec "update ${TASK_TABLENAME} set ${TEST_TYPE} = $(sql_quote "${status}") where commit_id = $(sql_quote "${commit_id}")"
}

mark_older_commits_skip() {
    mysql_exec "update ${TASK_TABLENAME} set ${TEST_TYPE} = 'skip' where ${TEST_TYPE} is NULL and commit_date_time < $(sql_quote "${commit_date_time}")"
}

query_next_commit() {
    local status_filter="$1"

    if [ "${status_filter}" = "retest" ]; then
        mysql_exec "SELECT commit_id, author, commit_date_time FROM ${TASK_TABLENAME} WHERE ${TEST_TYPE} = 'retest' ORDER BY commit_date_time desc LIMIT 1"
    else
        mysql_exec "SELECT commit_id, author, commit_date_time FROM ${TASK_TABLENAME} WHERE ${TEST_TYPE} is NULL ORDER BY commit_date_time desc LIMIT 1"
    fi
}

fetch_next_commit() {
    local row=""
    local raw_commit_date_time=""

    row="$(query_next_commit "retest")"
    if [ -z "${row}" ]; then
        row="$(query_next_commit "pending")"
    fi
    [ -n "${row}" ] || return 1

    IFS=$'\t' read -r commit_id author raw_commit_date_time <<< "${row}"
    author="$(trim "${author}")"
    commit_date_time="$(normalize_datetime "${raw_commit_date_time}")"
    [ -n "${commit_id}" ] || return 1
    [ -n "${commit_date_time}" ] || die "commit_date_time 解析失败"
}

mark_test_in_progress() {
    mkdir -p "${INIT_PATH}"
    printf 'ontesting\n' > "${INIT_PATH}/test_type_file"
}

restore_test_type_file() {
    mkdir -p "${INIT_PATH}"
    printf '%s\n' "${TEST_TYPE}" > "${INIT_PATH}/test_type_file"
}

reset_suite_metrics() {
    start_time=""
    end_time=""
    cost_time=0
}

stop_active_test() {
    if [ "${active_test_pid}" -gt 0 ] 2>/dev/null; then
        if kill -0 "${active_test_pid}" 2>/dev/null; then
            kill "${active_test_pid}" 2>/dev/null || true
            sleep 1
            kill -9 "${active_test_pid}" 2>/dev/null || true
        fi
        wait "${active_test_pid}" 2>/dev/null || true
    fi
    active_test_pid=0
}

check_pid_and_kill() {
    local pname="$1"
    local desc="$2"
    local pids=""
    local pid=""

    pids="$(jps | awk -v pname="${pname}" '$2 == pname {print $1}')"
    if [ -z "${pids}" ]; then
        log "未检测到${desc}"
        return 0
    fi

    while IFS= read -r pid; do
        [ -n "${pid}" ] || continue
        kill -9 "${pid}" 2>/dev/null || true
    done <<< "${pids}"

    log "${desc}已停止"
}

check_iotdb_pid() {
    check_pid_and_kill "DataNode" "DataNode 进程"
    check_pid_and_kill "ConfigNode" "ConfigNode 进程"
    check_pid_and_kill "IoTDB" "IoTDB 进程"
}

cleanup_processes() {
    stop_active_test
    check_iotdb_pid
}

set_env() {
    local source_path="${REPOS_PATH}/${commit_id}/apache-iotdb"

    require_directory "${source_path}" "待测版本目录"
    require_directory "${TOOL_PATH}" "SQL 测试工具目录"

    safe_rm "${TEST_IOTDB_PATH}"
    safe_rm "${TEST_TOOL_PATH}"

    mkdir -p "${TEST_IOTDB_PATH}/activation"
    mkdir -p "${TEST_TOOL_PATH}"

    cp -rf "${source_path}/." "${TEST_IOTDB_PATH}/"
    cp -rf "${TOOL_PATH}/." "${TEST_TOOL_PATH}/"
    copy_if_exists "${ATMOS_PATH}/conf/${TEST_TYPE}/license" "${TEST_IOTDB_PATH}/activation/" "license"
    copy_if_exists "${ATMOS_PATH}/conf/${TEST_TYPE}/env" "${TEST_IOTDB_PATH}/.env" "env"
}

modify_iotdb_config() {
    local datanode_env="${TEST_IOTDB_PATH}/conf/datanode-env.sh"
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"

    require_file "${datanode_env}" "datanode-env.sh"
    require_file "${properties_file}" "iotdb-system.properties"

    sed -i 's/^#\?ON_HEAP_MEMORY=.*$/ON_HEAP_MEMORY="20G"/' "${datanode_env}"

    cat >> "${properties_file}" <<EOF
dn_metric_internal_reporter_type=MEMORY
enable_seq_space_compaction=false
enable_unseq_space_compaction=false
enable_cross_space_compaction=false
cluster_name=${TEST_TYPE}
cn_enable_metric=true
cn_enable_performance_stat=true
cn_metric_reporter_list=PROMETHEUS
cn_metric_level=ALL
cn_metric_prometheus_reporter_port=9081
dn_enable_metric=true
dn_enable_performance_stat=true
dn_metric_reporter_list=PROMETHEUS
dn_metric_level=ALL
dn_metric_prometheus_reporter_port=9091
trusted_uri_pattern=.*
enforce_strong_password=true
enable_audit_log=true
EOF
}

set_protocol_class() {
    local protocol_code="$1"
    local config_node="${protocol_code:0:1}"
    local schema_region="${protocol_code:1:1}"
    local data_region="${protocol_code:2:1}"
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"

    [ "${#protocol_code}" -eq 3 ] || return 1
    [ -n "${PROTOCOL_CLASS[${config_node}]:-}" ] || return 1
    [ -n "${PROTOCOL_CLASS[${schema_region}]:-}" ] || return 1
    [ -n "${PROTOCOL_CLASS[${data_region}]:-}" ] || return 1

    cat >> "${properties_file}" <<EOF
config_node_consensus_protocol_class=${PROTOCOL_CLASS[${config_node}]}
schema_region_consensus_protocol_class=${PROTOCOL_CLASS[${schema_region}]}
data_region_consensus_protocol_class=${PROTOCOL_CLASS[${data_region}]}
EOF
}

start_iotdb() {
    (
        cd "${TEST_IOTDB_PATH}" || exit 1
        ./sbin/start-confignode.sh >/dev/null 2>&1 &
    )
    sleep "${STARTUP_GRACE_SECONDS}"
    (
        cd "${TEST_IOTDB_PATH}" || exit 1
        ./sbin/start-datanode.sh -H "${TEST_IOTDB_PATH}/dn_dump.hprof" >/dev/null 2>&1 &
    )
}

stop_iotdb() {
    if [ ! -d "${TEST_IOTDB_PATH}" ]; then
        return 0
    fi

    (
        cd "${TEST_IOTDB_PATH}" || exit 1
        ./sbin/stop-datanode.sh >/dev/null 2>&1 &
    )
    sleep "${STARTUP_GRACE_SECONDS}"
    (
        cd "${TEST_IOTDB_PATH}" || exit 1
        ./sbin/stop-confignode.sh >/dev/null 2>&1 &
    )
}

wait_for_iotdb_ready() {
    local attempt=0
    local iotdb_state=""

    for ((attempt = 1; attempt <= IOTDB_READY_RETRIES; attempt++)); do
        iotdb_state="$("${TEST_IOTDB_PATH}/sbin/start-cli.sh" -e "show cluster" 2>/dev/null | grep -F 'Total line number = 2' || true)"
        if [ "${iotdb_state}" = "Total line number = 2" ]; then
            return 0
        fi
        sleep "${IOTDB_READY_INTERVAL_SECONDS}"
    done

    return 1
}

sync_testcase_repo() {
    require_directory "${TESTCASE_PATH}" "SQL 测试用例目录"

    if [ -d "${TESTCASE_PATH}/.git" ]; then
        if ! (cd "${TESTCASE_PATH}" && timeout "${TESTCASE_PULL_TIMEOUT_SECONDS}s" git pull >/dev/null 2>&1); then
            log "同步 SQL 测试用例仓库失败，继续使用本地版本"
        fi
    else
        log "SQL 测试用例目录不是 git 仓库，跳过同步"
    fi
}

insert_result_row() {
    local remark="$1"
    local pass_value="$2"
    local fail_value="$3"
    local row_start_time="$4"
    local row_end_time="$5"
    local row_cost_time="$6"
    local insert_sql=""

    insert_sql=$(cat <<EOF
insert into ${TABLENAME} (
    commit_date_time,test_date_time,commit_id,author,pass_num,fail_num,start_time,end_time,cost_time,remark
) values (
    ${commit_date_time},
    ${test_date_time},
    $(sql_quote "${commit_id}"),
    $(sql_quote "${author}"),
    ${pass_value},
    ${fail_value},
    $(sql_quote "${row_start_time}"),
    $(sql_quote "${row_end_time}"),
    ${row_cost_time},
    $(sql_quote "${remark}")
)
EOF
)

    mysql_exec "${insert_sql}"
}

record_first_insert_result() {
    local first_start_ms=0
    local first_end_ms=0
    local first_cost_ms=0

    first_start_ms="$(current_millis)"
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" -e "${FIRST_INSERT_SQL}" >/dev/null 2>&1 || true
    first_end_ms="$(current_millis)"
    first_cost_ms=$((first_end_ms - first_start_ms))
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" -e "${RESET_TREE_SQL}" >/dev/null 2>&1 || true

    insert_result_row "${FIRST_INSERT_REMARK}" 0 0 "${first_start_ms}" "${first_end_ms}" "${first_cost_ms}"
}

configure_test_tool_user() {
    local testcase_mode_dir="$1"

    safe_rm "${TEST_TOOL_PATH}/user/scripts"
    safe_rm "${TEST_TOOL_PATH}/user/CONFIG"
    safe_rm "${TEST_TOOL_PATH}/result.xml"

    require_directory "${TESTCASE_PATH}/${testcase_mode_dir}/scripts" "${testcase_mode_dir} scripts"
    require_directory "${TESTCASE_PATH}/${testcase_mode_dir}/CONFIG" "${testcase_mode_dir} CONFIG"
    require_directory "${TEST_IOTDB_PATH}/lib" "IoTDB lib"

    mkdir -p "${TEST_TOOL_PATH}/user"
    copy_required_path "${TESTCASE_PATH}/${testcase_mode_dir}/scripts" "${TEST_TOOL_PATH}/user/" "${testcase_mode_dir} scripts"
    copy_required_path "${TESTCASE_PATH}/${testcase_mode_dir}/CONFIG" "${TEST_TOOL_PATH}/user/" "${testcase_mode_dir} CONFIG"

    mkdir -p "${TEST_TOOL_PATH}/user/driver/iotdb"
    cp -rf "${TEST_IOTDB_PATH}/lib/." "${TEST_TOOL_PATH}/user/driver/iotdb/"
}

prepare_mode_resources() {
    local mode="$1"

    require_directory "${TESTCASE_PATH}/lib" "SQL 测试依赖目录"
    mkdir -p "${TEST_IOTDB_PATH}/ext/trigger" "${TEST_IOTDB_PATH}/ext/udf"

    clear_directory_contents "${NGINX_DATA_PATH}"
    clear_directory_contents "${TSFILE_DATA_PATH}"
    copy_required_dir_contents "${TESTCASE_PATH}/tsfile" "${TSFILE_DATA_PATH}" "tsfile 测试数据"

    case "${mode}" in
        treemode)
            copy_required_dir_contents "${TESTCASE_PATH}/lib/trigger_jar/ext" "${TEST_IOTDB_PATH}/ext/trigger" "trigger ext 依赖"
            copy_required_dir_contents "${TESTCASE_PATH}/lib/udf_jar/envelop" "${TEST_IOTDB_PATH}/ext/udf" "udf envelop 依赖"
            copy_required_dir_contents "${TESTCASE_PATH}/lib/udf_jar/ext" "${TEST_IOTDB_PATH}/ext/udf" "udf ext 依赖"
            copy_required_dir_contents "${TESTCASE_PATH}/lib/udf_jar/example" "${TEST_IOTDB_PATH}/ext/udf" "udf example 依赖"
            copy_required_dir_contents "${TESTCASE_PATH}/lib/trigger_jar/local" "${NGINX_DATA_PATH}" "trigger 本地依赖"
            copy_required_dir_contents "${TESTCASE_PATH}/lib/udf_jar/local" "${NGINX_DATA_PATH}" "udf 本地依赖"
            copy_required_dir_contents "${TESTCASE_PATH}/lib/pipe_jar/local" "${NGINX_DATA_PATH}" "pipe 本地依赖"
            configure_test_tool_user "tree"
            ;;
        tablemode)
            copy_required_dir_contents "${TESTCASE_PATH}/lib/udf_jar/local" "${NGINX_DATA_PATH}" "udf 本地依赖"
            copy_required_dir_contents "${TESTCASE_PATH}/lib/pipe_jar/local" "${NGINX_DATA_PATH}" "pipe 本地依赖"
            copy_required_dir_contents "${TESTCASE_PATH}/lib/udf_jar/example" "${TEST_IOTDB_PATH}/ext/udf" "udf example 依赖"
            configure_test_tool_user "table"
            ;;
        *)
            die "未知测试模式: ${mode}"
            ;;
    esac
}

compile_test_tool() {
    require_file "${TEST_TOOL_PATH}/compile.sh" "compile.sh"
    (
        cd "${TEST_TOOL_PATH}" || exit 1
        ./compile.sh >/dev/null 2>&1
    )
}

monitor_result_file() {
    local result_file="${TEST_TOOL_PATH}/result.xml"
    local start_epoch=0
    local now_epoch=0
    local elapsed=0

    start_epoch="$(datetime_to_epoch "${start_time}")"
    while true; do
        if [ -f "${result_file}" ]; then
            end_time="$(current_datetime)"
            return 0
        fi

        now_epoch="$(date +%s)"
        elapsed=$((now_epoch - start_epoch))
        if [ "${elapsed}" -ge "${RESULT_TIMEOUT_SECONDS}" ]; then
            end_time="$(current_datetime)"
            stop_active_test
            return 1
        fi

        sleep "${RESULT_POLL_INTERVAL_SECONDS}"
    done
}

start_test_tool() {
    require_file "${TEST_TOOL_PATH}/test.sh" "test.sh"

    safe_rm "${TEST_TOOL_PATH}/result.xml"
    start_time="$(current_datetime)"
    (
        cd "${TEST_TOOL_PATH}" || exit 1
        exec ./test.sh >/dev/null 2>&1
    ) &
    active_test_pid=$!
}

parse_result_counts() {
    local result_file="${TEST_TOOL_PATH}/result.xml"
    local pass_value=0
    local fail_value=0

    require_file "${result_file}" "result.xml"
    pass_value="$(grep -c 'run" result="PASS"' "${result_file}" || true)"
    fail_value="$(grep -c 'run" result="FAIL"' "${result_file}" || true)"
    printf '%s\t%s\n' "${pass_value}" "${fail_value}"
}

mode_startup_wait_seconds() {
    local mode="$1"

    case "${mode}" in
        treemode)
            printf '%s\n' "${TREE_STARTUP_WAIT_SECONDS}"
            ;;
        tablemode)
            printf '%s\n' "${TABLE_STARTUP_WAIT_SECONDS}"
            ;;
        *)
            die "未知测试模式: ${mode}"
            ;;
    esac
}

backup_test_data() {
    local mode="$1"
    local backup_parent="${BACKUP_PATH}/${mode}"
    local backup_dir="${backup_parent}/${commit_date_time}_${commit_id}_${PROTOCOL_CODE}"

    sudo_safe_rm "${backup_dir}"
    path_is_safe "${backup_parent}" || die "拒绝使用非预期备份路径: ${backup_parent}"
    sudo mkdir -p -- "${backup_parent}"
    path_is_safe "${backup_dir}" || die "拒绝使用非预期备份路径: ${backup_dir}"
    sudo mkdir -p -- "${backup_dir}"

    if [ -d "${TEST_IOTDB_PATH}" ]; then
        sudo_safe_rm "${TEST_IOTDB_PATH}/data"
        path_is_safe "${TEST_IOTDB_PATH}" || die "拒绝移动非预期路径: ${TEST_IOTDB_PATH}"
        sudo mv "${TEST_IOTDB_PATH}" "${backup_dir}"
    fi

    if [ -d "${TEST_TOOL_PATH}" ]; then
        path_is_safe "${TEST_TOOL_PATH}" || die "拒绝移动非预期路径: ${TEST_TOOL_PATH}"
        sudo mv "${TEST_TOOL_PATH}" "${backup_dir}"
    fi
}

record_startup_failure() {
    local remark="$1"
    local failure_time=""

    failure_time="$(current_datetime)"
    insert_result_row "${remark}" 0 -3 "${failure_time}" "${failure_time}" -3
}

record_compile_failure() {
    local remark="$1"
    local failure_time=""

    failure_time="$(current_datetime)"
    insert_result_row "${remark}" 0 -2 "${failure_time}" "${failure_time}" -2
}

run_mode_suite() {
    local mode="$1"
    local suite_failed=0
    local startup_wait_seconds=0
    local remark=""
    local pass_value=0
    local fail_value=0
    local result_counts=""

    case "${mode}" in
        treemode)
            remark="${TREE_REMARK}"
            ;;
        tablemode)
            remark="${TABLE_REMARK}"
            ;;
        *)
            die "未知测试模式: ${mode}"
            ;;
    esac

    reset_suite_metrics
    test_date_time="$(date +%Y%m%d%H%M%S)"
    startup_wait_seconds="$(mode_startup_wait_seconds "${mode}")"

    log "开始执行 ${mode} 测试"
    cleanup_processes
    set_env
    modify_iotdb_config

    if ! set_protocol_class "${PROTOCOL_CODE}"; then
        die "协议配置无效: ${PROTOCOL_CODE}"
    fi

    start_iotdb
    sleep "${startup_wait_seconds}"
    if ! wait_for_iotdb_ready; then
        log "${mode} 模式下 IoTDB 未能正常启动，记录失败结果"
        record_startup_failure "${remark}"
        suite_failed=1
        stop_iotdb
        sleep "${SHUTDOWN_WAIT_SECONDS}"
        cleanup_processes
        backup_test_data "${mode}"
        return "${suite_failed}"
    fi

    if [ "${mode}" = "treemode" ]; then
        record_first_insert_result
    fi

    prepare_mode_resources "${mode}"
    if ! compile_test_tool; then
        log "${mode} 模式测试工具编译失败，记录失败结果"
        record_compile_failure "${remark}"
        suite_failed=1
        stop_iotdb
        sleep "${SHUTDOWN_WAIT_SECONDS}"
        cleanup_processes
        backup_test_data "${mode}"
        return "${suite_failed}"
    fi

    start_test_tool
    if ! monitor_result_file; then
        log "${mode} 模式测试超时，记录失败结果"
        pass_value=0
        fail_value=-1
        suite_failed=1
    else
        result_counts="$(parse_result_counts)"
        IFS=$'\t' read -r pass_value fail_value <<< "${result_counts}"
    fi

    stop_iotdb
    sleep "${SHUTDOWN_WAIT_SECONDS}"
    cleanup_processes

    cost_time=$(( $(datetime_to_epoch "${end_time}") - $(datetime_to_epoch "${start_time}") ))
    insert_result_row "${remark}" "${pass_value}" "${fail_value}" "${start_time}" "${end_time}" "${cost_time}"
    backup_test_data "${mode}"
    log "${mode} 测试已完成，PASS=${pass_value}，FAIL=${fail_value}"

    return "${suite_failed}"
}

main() {
    local mode=""
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
    log "当前版本 ${commit_id} 未执行过测试，开始 SQL 覆盖率测试流程"
    sync_testcase_repo

    for mode in "${MODE_LIST[@]}"; do
        if ! run_mode_suite "${mode}"; then
            task_failed=1
        fi
    done

    log "本轮 SQL 覆盖率测试 ${test_date_time} 已结束"
    if [ "${task_failed}" -eq 0 ]; then
        update_task_status "done"
        mark_older_commits_skip
    else
        update_task_status "RError"
    fi
}

main "$@"
