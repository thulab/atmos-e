#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "runtime_common.sh 需要使用 bash 运行" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "runtime_common.sh 需要使用非 posix 模式的 bash 运行" >&2
    return 1 2>/dev/null || exit 1
fi

: "${TEST_IP:?在 source runtime_common.sh 之前必须设置 TEST_IP}"
: "${TEST_TYPE:?在 source runtime_common.sh 之前必须设置 TEST_TYPE}"

readonly BACKUP_PATH="/nasdata/repository/${TEST_TYPE}"
readonly INIT_PATH="/root/zk_test"
readonly ATMOS_PATH="${INIT_PATH}/atmos-e"
readonly BM_PATH="${INIT_PATH}/iot-benchmark"
readonly REPOS_PATH="/nasdata/repository/master"
readonly BM_REPOS_PATH="/nasdata/repository/iot-benchmark"

readonly TEST_INIT_PATH="/data/qa"
readonly TEST_IOTDB_PATH="${TEST_INIT_PATH}/apache-iotdb"

if ! declare -p PROTOCOL_CLASS >/dev/null 2>&1; then
    readonly -a PROTOCOL_CLASS=(
        ""
        "org.apache.iotdb.consensus.simple.SimpleConsensus"
        "org.apache.iotdb.consensus.ratis.RatisConsensus"
        "org.apache.iotdb.consensus.iot.IoTConsensus"
        "org.apache.iotdb.consensus.iot.IoTConsensusV2"
    )
fi
if ! declare -p METRIC_SERVER >/dev/null 2>&1; then
    readonly METRIC_SERVER="172.20.70.11:9090"
else
    readonly METRIC_SERVER
fi
if ! declare -p ENABLE_BENCHMARK_VERSION_CHECK >/dev/null 2>&1; then
    readonly ENABLE_BENCHMARK_VERSION_CHECK=1
else
    readonly ENABLE_BENCHMARK_VERSION_CHECK
fi
if ! declare -p MONITOR_TIMEOUT_SECONDS >/dev/null 2>&1; then
    readonly MONITOR_TIMEOUT_SECONDS=7200
else
    readonly MONITOR_TIMEOUT_SECONDS
fi
if ! declare -p MONITOR_POLL_INTERVAL_SECONDS >/dev/null 2>&1; then
    readonly MONITOR_POLL_INTERVAL_SECONDS=10
else
    readonly MONITOR_POLL_INTERVAL_SECONDS
fi
if ! declare -p IOTDB_READY_RETRIES >/dev/null 2>&1; then
    readonly IOTDB_READY_RETRIES=10
else
    readonly IOTDB_READY_RETRIES
fi
if ! declare -p IOTDB_READY_INTERVAL_SECONDS >/dev/null 2>&1; then
    readonly IOTDB_READY_INTERVAL_SECONDS=5
else
    readonly IOTDB_READY_INTERVAL_SECONDS
fi
if ! declare -p STARTUP_GRACE_SECONDS >/dev/null 2>&1; then
    readonly STARTUP_GRACE_SECONDS=10
else
    readonly STARTUP_GRACE_SECONDS
fi
if ! declare -p BENCHMARK_WARMUP_SECONDS >/dev/null 2>&1; then
    readonly BENCHMARK_WARMUP_SECONDS=10
else
    readonly BENCHMARK_WARMUP_SECONDS
fi
if ! declare -p BENCHMARK_STOP_WAIT_SECONDS >/dev/null 2>&1; then
    readonly BENCHMARK_STOP_WAIT_SECONDS=30
else
    readonly BENCHMARK_STOP_WAIT_SECONDS
fi

readonly MYSQLHOSTNAME="111.200.37.158"
readonly PORT="13306"
readonly USERNAME="iotdbatm"
readonly PASSWORD="${ATMOS_DB_PASSWORD:-}"
readonly DBNAME="QA_ATM"
readonly TASK_TABLENAME="commit_history"

commit_id=""
author=""
commit_date_time=""
test_date_time=""
ts_type=""
data_type=""
start_time=""
end_time=""
cost_time=0
m_start_time=0
m_end_time=0

okPoint=0
okOperation=0
failPoint=0
failOperation=0
throughput=0
Latency=0
MIN=0
P10=0
P25=0
MEDIAN=0
P75=0
P90=0
P95=0
P99=0
P999=0
MAX=0
numOfSe0Level=0
numOfUnse0Level=0
dataFileSize=0
maxNumofOpenFiles=0
maxNumofThread=0
errorLogSize=0
walFileSize=0

IOTDB_READY_USER="${IOTDB_READY_USER:-}"
IOTDB_READY_PASSWORD="${IOTDB_READY_PASSWORD:-}"

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

datetime_to_epoch() {
    date -d "$1" +%s
}

normalize_datetime() {
    printf '%s' "$1" | tr -cd '0-9'
}

append_iotdb_properties() {
    local properties_file="$1"

    :
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "缺少依赖命令: $1"
}

check_password() {
    [ -n "${PASSWORD}" ] || die "ATMOS_DB_PASSWORD 未设置，无法连接 MySQL"
}

ensure_base_runtime_dependencies() {
    local cmd=""

    for cmd in awk cat cp curl date du grep jq jps kill mkdir mv mysql rm sed sudo tr wc; do
        require_command "${cmd}"
    done
}

ensure_runtime_dependencies() {
    ensure_base_runtime_dependencies
}

path_is_safe() {
    local path="$1"

    [ -n "${path}" ] || return 1

    case "${path}" in
        "/"|"/data"|"/nasdata"|".")
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

emit_query_name_candidates() {
    local current_name="$1"
    local alternate_name=""

    printf '%s\n' "${current_name}"
    if [[ "${current_name}" =~ ^(Q[0-9]+)-([ab])([0-9]+)$ ]]; then
        alternate_name="${BASH_REMATCH[1]}${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    elif [[ "${current_name}" =~ ^(Q[0-9]+)([ab])-([0-9]+)$ ]]; then
        alternate_name="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    fi

    if [ -n "${alternate_name}" ] && [ "${alternate_name}" != "${current_name}" ]; then
        printf '%s\n' "${alternate_name}"
    fi
}

resolve_config_from_roots() {
    local config_name="$1"
    shift
    local root=""
    local candidate_name=""
    local candidate_path=""

    for root in "$@"; do
        [ -n "${root}" ] || continue
        while IFS= read -r candidate_name; do
            [ -n "${candidate_name}" ] || continue
            candidate_path="${root}/${candidate_name}"
            if [ -f "${candidate_path}" ]; then
                printf '%s\n' "${candidate_path}"
                return 0
            fi
        done < <(emit_query_name_candidates "${config_name}")
    done

    return 1
}

build_scoped_path() {
    local base_path="${1%/}"
    shift
    local current_segment=""
    local path="${base_path}"

    for current_segment in "$@"; do
        current_segment="$(trim "${current_segment}")"
        [ -n "${current_segment}" ] || continue
        current_segment="${current_segment// /_}"
        current_segment="${current_segment//\//_}"
        path="${path}/${current_segment}"
    done

    printf '%s\n' "${path}"
}

prepare_backup_directory() {
    local backup_dir="$1"
    local backup_parent="${backup_dir%/*}"

    sudo_safe_rm "${backup_dir}"
    path_is_safe "${backup_parent}" || die "拒绝使用非预期备份路径: ${backup_parent}"
    sudo mkdir -p -- "${backup_parent}"
    path_is_safe "${backup_dir}" || die "拒绝使用非预期备份路径: ${backup_dir}"
    sudo mkdir -p -- "${backup_dir}"
}

archive_test_runtime_artifacts() {
    local backup_dir="$1"
    local csv_source="${2:-${BM_PATH}/data/csvOutput}"
    local iotdb_target="${backup_dir}/iotdb"

    prepare_backup_directory "${backup_dir}"

    sudo_safe_rm "${TEST_IOTDB_PATH}/data"
    path_is_safe "${TEST_IOTDB_PATH}" || die "拒绝移动非预期路径: ${TEST_IOTDB_PATH}"
    sudo mv "${TEST_IOTDB_PATH}" "${iotdb_target}"

    if [ -d "${csv_source}" ]; then
        sudo cp -rf "${csv_source}" "${backup_dir}/"
    fi
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

check_benchmark_version() {
    local bm_new=""
    local bm_old=""

    [ -f "${BM_REPOS_PATH}/git.properties" ] || die "缺少 benchmark git.properties: ${BM_REPOS_PATH}/git.properties"
    bm_new="$(awk -F= '/git.commit.id.abbrev/ {print $2}' "${BM_REPOS_PATH}/git.properties")"
    [ -n "${bm_new}" ] || die "无法读取 benchmark 版本信息"

    if [ -f "${BM_PATH}/git.properties" ]; then
        bm_old="$(awk -F= '/git.commit.id.abbrev/ {print $2}' "${BM_PATH}/git.properties")"
    fi

    if [ ! -d "${BM_PATH}" ] || [ "${bm_old}" != "${bm_new}" ]; then
        log "同步 benchmark 目录到最新版本"
        mkdir -p "${INIT_PATH}"
        safe_rm "${BM_PATH}"
        cp -rf "${BM_REPOS_PATH}" "${BM_PATH}"
    fi
}

init_common_items() {
    okPoint=0
    okOperation=0
    failPoint=0
    failOperation=0
    throughput=0
    Latency=0
    MIN=0
    P10=0
    P25=0
    MEDIAN=0
    P75=0
    P90=0
    P95=0
    P99=0
    P999=0
    MAX=0
    numOfSe0Level=0
    numOfUnse0Level=0
    start_time=""
    end_time=""
    cost_time=0
    dataFileSize=0
    maxNumofOpenFiles=0
    maxNumofThread=0
    errorLogSize=0
    walFileSize=0
    m_start_time=0
    m_end_time=0
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
        kill -9 "${pid}"
    done <<< "${pids}"

    log "${desc}已停止"
}

check_benchmark_pid() {
    check_pid_and_kill "App" "benchmark 进程"
}

check_iotdb_pid() {
    check_pid_and_kill "DataNode" "DataNode 进程"
    check_pid_and_kill "ConfigNode" "ConfigNode 进程"
    check_pid_and_kill "IoTDB" "IoTDB 进程"
}

cleanup_processes() {
    check_benchmark_pid
    check_iotdb_pid
}

set_env() {
    local source_path="${REPOS_PATH}/${commit_id}/apache-iotdb"

    [ -d "${source_path}" ] || die "缺少待测版本目录: ${source_path}"

    safe_rm "${TEST_IOTDB_PATH}"
    mkdir -p "${TEST_IOTDB_PATH}/activation"
    cp -rf "${source_path}/." "${TEST_IOTDB_PATH}/"
    copy_if_exists "${ATMOS_PATH}/conf/${TEST_TYPE}/license" "${TEST_IOTDB_PATH}/activation/" "license"
    copy_if_exists "${ATMOS_PATH}/conf/${TEST_TYPE}/env" "${TEST_IOTDB_PATH}/.env" "env"
}

modify_iotdb_config() {
    local datanode_env="${TEST_IOTDB_PATH}/conf/datanode-env.sh"
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"

    [ -f "${datanode_env}" ] || die "缺少配置文件: ${datanode_env}"
    [ -f "${properties_file}" ] || die "缺少配置文件: ${properties_file}"

    sed -i 's/^#\?ON_HEAP_MEMORY=.*$/ON_HEAP_MEMORY="20G"/' "${datanode_env}"

    cat >> "${properties_file}" <<EOF
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
EOF

    append_iotdb_properties "${properties_file}"
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

start_benchmark() {
    safe_rm "${BM_PATH}/logs"
    safe_rm "${BM_PATH}/data"
    (
        cd "${BM_PATH}" || exit 1
        ./benchmark.sh >/dev/null 2>&1 &
    )
}

wait_for_iotdb_ready() {
    local attempt=0
    local iotdb_state=""
    local -a cli_args=()

    if [ -n "${IOTDB_READY_USER}" ]; then
        cli_args+=(-u "${IOTDB_READY_USER}")
    fi
    if [ -n "${IOTDB_READY_PASSWORD}" ]; then
        cli_args+=(-pw "${IOTDB_READY_PASSWORD}")
    fi

    for ((attempt = 1; attempt <= IOTDB_READY_RETRIES; attempt++)); do
        if [ "${#cli_args[@]}" -gt 0 ]; then
            iotdb_state="$("${TEST_IOTDB_PATH}/sbin/start-cli.sh" "${cli_args[@]}" -e "show cluster" 2>/dev/null | grep -F 'Total line number = 2' || true)"
        else
            iotdb_state="$("${TEST_IOTDB_PATH}/sbin/start-cli.sh" -e "show cluster" 2>/dev/null | grep -F 'Total line number = 2' || true)"
        fi
        if [ "${iotdb_state}" = "Total line number = 2" ]; then
            return 0
        fi
        sleep "${IOTDB_READY_INTERVAL_SECONDS}"
    done

    return 1
}

find_result_csv() {
    local had_nullglob=0
    local files=()

    if shopt -q nullglob; then
        had_nullglob=1
    else
        shopt -s nullglob
    fi

    files=("${BM_PATH}/data/csvOutput/"*result.csv)

    if [ "${had_nullglob}" -eq 0 ]; then
        shopt -u nullglob
    fi

    if [ "${#files[@]}" -gt 0 ]; then
        printf '%s\n' "${files[0]}"
    fi
}

create_stuck_result_csv() {
    local csv_file="$1"
    local result_label="$2"
    local index=0

    mkdir -p "${csv_file%/*}"
    : > "${csv_file}"
    for ((index = 0; index < 100; index++)); do
        printf '%s ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1\n' "${result_label}" >> "${csv_file}"
    done
}

monitor_test_status() {
    local current_name="$1"
    local result_label="$2"
    local csv_file=""
    local now_epoch=0
    local elapsed=0

    while true; do
        csv_file="$(find_result_csv || true)"
        if [ -n "${csv_file}" ]; then
            end_time="$(current_datetime)"
            log "${current_name} 已完成"
            return 0
        fi

        now_epoch="$(date +%s)"
        elapsed=$((now_epoch - m_start_time))
        if [ "${elapsed}" -ge "${MONITOR_TIMEOUT_SECONDS}" ]; then
            end_time="$(current_datetime)"
            log "${current_name} 超时，写入兜底结果"
            create_stuck_result_csv "${BM_PATH}/data/csvOutput/Stuck_result.csv" "${result_label}"
            return 1
        fi

        sleep "${MONITOR_POLL_INTERVAL_SECONDS}"
    done
}

get_single_index() {
    local query="$1"
    local end="$2"
    local index_value=""

    index_value="$(
        curl -G -s "http://${METRIC_SERVER}/api/v1/query" \
            --data-urlencode "query=${query}" \
            --data-urlencode "time=${end}" \
            | jq -r '.data.result[0].value[1] // 0'
    )"

    if [ "${index_value}" = "null" ] || [ -z "${index_value}" ]; then
        index_value=0
    fi

    printf '%s\n' "${index_value}"
}

bytes_to_gib() {
    awk -v value="${1:-0}" 'BEGIN { printf "%.2f\n", value / 1073741824 }'
}

to_int() {
    awk -v value="${1:-0}" 'BEGIN { printf "%d\n", value }'
}

collect_error_log_size() {
    local datanode_error_log_file="${TEST_IOTDB_PATH}/logs/log_datanode_error.log"
    local confignode_error_log_file="${TEST_IOTDB_PATH}/logs/log_confignode_error.log"
    local datanode_error_log_size=0
    local confignode_error_log_size=0

    datanode_error_log_size="$(du -sb "${datanode_error_log_file}" 2>/dev/null | awk '{print $1}')"
    confignode_error_log_size="$(du -sb "${confignode_error_log_file}" 2>/dev/null | awk '{print $1}')"
    printf '%s\n' "$(( ${datanode_error_log_size:-0} + ${confignode_error_log_size:-0} ))"
}

collect_monitor_snapshot() {
    local ip="${1:-${TEST_IP}}"
    local metric_time="${2:-$(date +%s)}"

    dataFileSize="$(get_single_index "sum(file_global_size{instance=~\"${ip}:9091\"})" "${metric_time}")"
    dataFileSize="$(bytes_to_gib "${dataFileSize}")"
    numOfSe0Level="$(get_single_index "sum(file_global_count{instance=~\"${ip}:9091\",name=\"seq\"})" "${metric_time}")"
    numOfUnse0Level="$(get_single_index "sum(file_global_count{instance=~\"${ip}:9091\",name=\"unseq\"})" "${metric_time}")"
}

collect_monitor_window_data() {
    local ip="${1:-${TEST_IP}}"
    local window_start_time="${2:-${m_start_time}}"
    local window_end_time="${3:-${m_end_time}}"
    local metric_window=$((window_end_time - window_start_time))
    local max_num_thread_c=0
    local max_num_thread_d=0

    if [ "${metric_window}" -le 0 ]; then
        metric_window=1
    fi

    collect_monitor_snapshot "${ip}" "${window_end_time}"
    max_num_thread_c="$(get_single_index "max_over_time(process_threads_count{instance=~\"${ip}:9081\"}[${metric_window}s])" "${window_end_time}")"
    max_num_thread_d="$(get_single_index "max_over_time(process_threads_count{instance=~\"${ip}:9091\"}[${metric_window}s])" "${window_end_time}")"
    maxNumofThread=$(( $(to_int "${max_num_thread_c}") + $(to_int "${max_num_thread_d}") ))
    maxNumofOpenFiles="$(get_single_index "max_over_time(file_count{instance=~\"${ip}:9091\",name=\"open_file_handlers\"}[${metric_window}s])" "${window_end_time}")"
    walFileSize="$(get_single_index "max_over_time(file_size{instance=~\"${ip}:9091\",name=~\"wal\"}[${metric_window}s])" "${window_end_time}")"
    walFileSize="$(bytes_to_gib "${walFileSize}")"
    errorLogSize="$(collect_error_log_size)"
}

collect_resource_monitor_data() {
    local ip="${1:-${TEST_IP}}"
    local disk_id_pattern="${2:-}"
    local window_start_time="${3:-${m_start_time}}"
    local window_end_time="${4:-${m_end_time}}"
    local metric_window=$((window_end_time - window_start_time))

    if [ "${metric_window}" -le 0 ]; then
        metric_window=1
    fi

    collect_monitor_window_data "${ip}" "${window_start_time}" "${window_end_time}"
    maxCPULoad="$(get_single_index "max_over_time(sys_cpu_load{instance=~\"${ip}:9091\"}[${metric_window}s])" "${window_end_time}")"
    avgCPULoad="$(get_single_index "avg_over_time(sys_cpu_load{instance=~\"${ip}:9091\"}[${metric_window}s])" "${window_end_time}")"

    if [ -n "${disk_id_pattern}" ]; then
        maxDiskIOOpsRead="$(get_single_index "sum(rate(disk_io_ops{instance=~\"${ip}:9091\",disk_id=~\"${disk_id_pattern}\",type=~\"read\"}[${metric_window}s]))" "${window_end_time}")"
        maxDiskIOOpsWrite="$(get_single_index "sum(rate(disk_io_ops{instance=~\"${ip}:9091\",disk_id=~\"${disk_id_pattern}\",type=~\"write\"}[${metric_window}s]))" "${window_end_time}")"
        maxDiskIOSizeRead="$(get_single_index "sum(rate(disk_io_size{instance=~\"${ip}:9091\",disk_id=~\"${disk_id_pattern}\",type=~\"read\"}[${metric_window}s]))" "${window_end_time}")"
        maxDiskIOSizeWrite="$(get_single_index "sum(rate(disk_io_size{instance=~\"${ip}:9091\",disk_id=~\"${disk_id_pattern}\",type=~\"write\"}[${metric_window}s]))" "${window_end_time}")"
    else
        maxDiskIOOpsRead=0
        maxDiskIOOpsWrite=0
        maxDiskIOSizeRead=0
        maxDiskIOSizeWrite=0
    fi
}

collect_common_monitor_data() {
    local ip="${1:-${TEST_IP}}"

    collect_monitor_window_data "${ip}" "${m_start_time}" "${m_end_time}"
}

copy_benchmark_config() {
    local config_source="$1"
    local config_target="${BM_PATH}/conf/config.properties"

    [ -f "${config_source}" ] || die "缺少 benchmark 配置文件: ${config_source}"
    safe_rm "${config_target}"
    cp -rf "${config_source}" "${config_target}"
}

mark_test_in_progress() {
    mkdir -p "${INIT_PATH}"
    printf 'ontesting\n' > "${INIT_PATH}/test_type_file"
}

restore_test_type_file() {
    mkdir -p "${INIT_PATH}"
    printf '%s\n' "${TEST_TYPE}" > "${INIT_PATH}/test_type_file"
}
