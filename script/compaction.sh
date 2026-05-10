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
readonly -a PROTOCOL_LIST=(211)
readonly -a TS_LIST=(common aligned)
readonly METRIC_SERVER="172.20.70.11:9090"

readonly BACKUP_PATH="/nasdata/repository/${TEST_TYPE}"
readonly DATASET_PATH="${DATA_PATH}"

readonly INIT_PATH="/root/zk_test"
readonly ATMOS_PATH="${INIT_PATH}/atmos-e"
readonly REPOS_PATH="/nasdata/repository/master"

readonly TEST_INIT_PATH="/data/qa"
readonly TEST_IOTDB_PATH="${TEST_INIT_PATH}/apache-iotdb"

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

readonly STARTUP_GRACE_SECONDS=10
readonly STOP_WAIT_SECONDS=30
readonly COMPACTION_INITIAL_WAIT_SECONDS=30
readonly COMPACTION_IDLE_CONFIRM_SECONDS=70
readonly COMPACTION_TIMEOUT_SECONDS=7200
readonly MONITOR_POLL_INTERVAL_SECONDS=10
readonly DEFAULT_TARGET_COMPACTION_FILE_SIZE=1073741824
readonly CROSS_TARGET_COMPACTION_FILE_SIZE=2147483648
readonly SEQ_READY_RETRIES=20
readonly SEQ_READY_INTERVAL_SECONDS=30
readonly UNSEQ_READY_RETRIES=10
readonly UNSEQ_READY_INTERVAL_SECONDS=5
readonly CROSS_READY_RETRIES=20
readonly CROSS_READY_INTERVAL_SECONDS=30
readonly DEFAULT_DISK_ID_REGEX="^vdc$"

commit_id=""
author=""
commit_date_time=""
test_date_time=""
ts_type=""
comp_type=""
cost_time=0
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
maxNumofOpenFiles=0
maxNumofThread=0
errorLogSize=0
maxCPULoad=0
avgCPULoad=0
maxDiskIOOpsRead=0
maxDiskIOOpsWrite=0
maxDiskIOSizeRead=0
maxDiskIOSizeWrite=0
m_start_time=0
m_end_time=0

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

trim() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

normalize_datetime() {
    printf '%s' "$1" | tr -cd '0-9'
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing dependency command: $1"
}

ensure_runtime_dependencies() {
    local cmd
    for cmd in awk cat cp curl date du find grep jq jps kill mkdir mv mysql rm sed sudo tail tr wc; do
        require_command "${cmd}"
    done
}

check_password() {
    if [ -z "${PASSWORD}" ]; then
        die "ATMOS_DB_PASSWORD is not set, cannot connect to MySQL"
    fi
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
    path_is_safe "${path}" || die "refuse to remove unexpected path: ${path}"
    rm -rf -- "${path}"
}

sudo_safe_rm() {
    local path="$1"
    [ -e "${path}" ] || return 0
    path_is_safe "${path}" || die "refuse to remove unexpected path: ${path}"
    sudo rm -rf -- "${path}"
}

copy_if_exists() {
    local source="$1"
    local target="$2"
    local label="${3:-$1}"

    if [ ! -e "${source}" ]; then
        log "skip copy, missing ${label}: ${source}"
        return 0
    fi

    cp -rf -- "${source}" "${target}"
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
    [ -n "${commit_date_time}" ] || die "failed to parse commit_date_time"
}

init_items() {
    ts_type=""
    comp_type=""
    cost_time=0
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
    maxNumofOpenFiles=0
    maxNumofThread=0
    errorLogSize=0
    maxCPULoad=0
    avgCPULoad=0
    maxDiskIOOpsRead=0
    maxDiskIOOpsWrite=0
    maxDiskIOSizeRead=0
    maxDiskIOSizeWrite=0
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
        log "did not detect ${desc}"
        return 0
    fi

    while IFS= read -r pid; do
        [ -n "${pid}" ] || continue
        kill -9 "${pid}"
    done <<< "${pids}"

    log "${desc} stopped"
}

check_iotdb_pid() {
    check_pid_and_kill "DataNode" "DataNode process"
    check_pid_and_kill "ConfigNode" "ConfigNode process"
    check_pid_and_kill "IoTDB" "IoTDB process"
}

cleanup_processes() {
    check_iotdb_pid
}

replace_or_append_property() {
    local file="$1"
    local key="$2"
    local value="$3"

    if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${file}"; then
        sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*$|${key}=${value}|" "${file}"
    else
        printf '%s=%s\n' "${key}" "${value}" >> "${file}"
    fi
}

apply_base_iotdb_config() {
    local datanode_env="${TEST_IOTDB_PATH}/conf/datanode-env.sh"
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"

    [ -f "${datanode_env}" ] || die "missing config file: ${datanode_env}"
    [ -f "${properties_file}" ] || die "missing config file: ${properties_file}"

    sed -i 's/^#\?ON_HEAP_MEMORY=.*$/ON_HEAP_MEMORY="20G"/' "${datanode_env}"
    replace_or_append_property "${properties_file}" "series_slot_num" "10000"
    replace_or_append_property "${properties_file}" "target_compaction_file_size" "${DEFAULT_TARGET_COMPACTION_FILE_SIZE}"
    replace_or_append_property "${properties_file}" "enable_seq_space_compaction" "false"
    replace_or_append_property "${properties_file}" "enable_unseq_space_compaction" "false"
    replace_or_append_property "${properties_file}" "enable_cross_space_compaction" "false"
    replace_or_append_property "${properties_file}" "cluster_name" "${TEST_TYPE}"
    replace_or_append_property "${properties_file}" "cn_enable_metric" "true"
    replace_or_append_property "${properties_file}" "cn_enable_performance_stat" "true"
    replace_or_append_property "${properties_file}" "cn_metric_reporter_list" "PROMETHEUS"
    replace_or_append_property "${properties_file}" "cn_metric_level" "ALL"
    replace_or_append_property "${properties_file}" "cn_metric_prometheus_reporter_port" "9081"
    replace_or_append_property "${properties_file}" "dn_enable_metric" "true"
    replace_or_append_property "${properties_file}" "dn_enable_performance_stat" "true"
    replace_or_append_property "${properties_file}" "dn_metric_reporter_list" "PROMETHEUS"
    replace_or_append_property "${properties_file}" "dn_metric_level" "ALL"
    replace_or_append_property "${properties_file}" "dn_metric_prometheus_reporter_port" "9091"
}

set_env() {
    local source_path="${REPOS_PATH}/${commit_id}/apache-iotdb"
    [ -d "${source_path}" ] || die "missing target commit directory: ${source_path}"

    safe_rm "${TEST_IOTDB_PATH}"
    mkdir -p "${TEST_IOTDB_PATH}/activation"
    cp -rf "${source_path}/." "${TEST_IOTDB_PATH}/"
    copy_if_exists "${ATMOS_PATH}/conf/${TEST_TYPE}/license" "${TEST_IOTDB_PATH}/activation/" "license"
    copy_if_exists "${ATMOS_PATH}/conf/${TEST_TYPE}/env" "${TEST_IOTDB_PATH}/.env" "env"
    apply_base_iotdb_config
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

    replace_or_append_property "${properties_file}" "config_node_consensus_protocol_class" "${PROTOCOL_CLASS[${config_node}]}"
    replace_or_append_property "${properties_file}" "schema_region_consensus_protocol_class" "${PROTOCOL_CLASS[${schema_region}]}"
    replace_or_append_property "${properties_file}" "data_region_consensus_protocol_class" "${PROTOCOL_CLASS[${data_region}]}"
}

copy_dataset() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local source_path="${DATASET_PATH}/${protocol_code}/${current_ts_type}/data"

    [ -d "${source_path}" ] || die "missing dataset path: ${source_path}"
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

    replace_or_append_property "${properties_file}" "target_compaction_file_size" "${target_file_size}"
    replace_or_append_property "${properties_file}" "enable_seq_space_compaction" "${seq_enabled}"
    replace_or_append_property "${properties_file}" "enable_unseq_space_compaction" "${unseq_enabled}"
    replace_or_append_property "${properties_file}" "enable_cross_space_compaction" "${cross_enabled}"
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

directory_size_bytes() {
    local target_path="$1"
    du -sb -- "${target_path}" 2>/dev/null | awk 'NR==1 { print $1 }'
}

bytes_to_gib() {
    awk -v value="${1:-0}" 'BEGIN { printf "%.2f\n", value / 1073741824 }'
}

to_int() {
    awk -v value="${1:-0}" 'BEGIN { printf "%d\n", value }'
}

count_level0_files() {
    local target_dir="$1"

    if [ ! -d "${target_dir}" ]; then
        printf '0\n'
        return 0
    fi

    find "${target_dir}" -name "*-0-*.tsfile" | wc -l
}

collect_data_before() {
    dataFileSize_before="$(bytes_to_gib "$(directory_size_bytes "${TEST_IOTDB_PATH}/data")")"
    numOfSe0Level_before="$(count_level0_files "${TEST_IOTDB_PATH}/data/datanode/data/sequence")"
    numOfUnse0Level_before="$(count_level0_files "${TEST_IOTDB_PATH}/data/datanode/data/unsequence")"
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
                log "${current_compaction_type} compaction finished"
                return 0
            fi
        fi

        now_epoch="$(date +%s)"
        elapsed=$((now_epoch - m_start_time))
        if [ "${elapsed}" -ge "${COMPACTION_TIMEOUT_SECONDS}" ]; then
            log "${current_compaction_type} compaction timed out, writing fallback log"
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

    comp_start_time="$(awk 'NR==1 { print substr($1 " " $2, 1, 19); exit }' "${log_file}")"
    comp_end_time="$(awk 'END { print substr($1 " " $2, 1, 19) }' "${log_file}")"
    line="$(grep -E 'InnerSpaceCompaction task finishes successfully|CrossSpaceCompaction task finishes successfully' "${log_file}" | tail -n 1 || true)"
    [ -n "${line}" ] || return 1

    cost_time="$(printf '%s\n' "${line}" | sed -n 's/.*time cost is \([-0-9.]\+\) s.*/\1/p')"
    [ -n "${cost_time}" ] || return 1
    [ -n "${comp_start_time}" ] || return 1
    [ -n "${comp_end_time}" ] || return 1
}

collect_data_after() {
    local datanode_error_bytes=0
    local confignode_error_bytes=0

    dataFileSize_after="$(bytes_to_gib "$(directory_size_bytes "${TEST_IOTDB_PATH}/data")")"
    numOfSe0Level_after="$(count_level0_files "${TEST_IOTDB_PATH}/data/datanode/data/sequence")"
    numOfUnse0Level_after="$(count_level0_files "${TEST_IOTDB_PATH}/data/datanode/data/unsequence")"
    compaction_rate=0
    ts_dataSize=0
    ts_numOfPoints=0

    if ! parse_compaction_log; then
        cost_time=-2
        comp_start_time="0"
        comp_end_time="0"
        return 1
    fi

    datanode_error_bytes="$(du -sb "${TEST_IOTDB_PATH}/logs/log_datanode_error.log" 2>/dev/null | awk 'NR==1 { print $1 }')"
    confignode_error_bytes="$(du -sb "${TEST_IOTDB_PATH}/logs/log_confignode_error.log" 2>/dev/null | awk 'NR==1 { print $1 }')"
    if [ "${datanode_error_bytes:-0}" -gt 0 ] || [ "${confignode_error_bytes:-0}" -gt 0 ]; then
        errorLogSize=1
    else
        errorLogSize=0
    fi
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

collect_monitor_metrics() {
    local ip="$1"
    local metric_window=$((m_end_time - m_start_time))
    local max_open_files_c=0
    local max_open_files_d=0
    local max_threads_c=0
    local max_threads_d=0

    if [ "${metric_window}" -le 0 ]; then
        metric_window=1
    fi

    max_open_files_c="$(get_single_index "max_over_time(file_count{instance=~\"${ip}:9081\",name=\"open_file_handlers\"}[${metric_window}s])" "${m_end_time}")"
    max_open_files_d="$(get_single_index "max_over_time(file_count{instance=~\"${ip}:9091\",name=\"open_file_handlers\"}[${metric_window}s])" "${m_end_time}")"
    maxNumofOpenFiles=$(( $(to_int "${max_open_files_c}") + $(to_int "${max_open_files_d}") ))
    max_threads_c="$(get_single_index "max_over_time(process_threads_count{instance=~\"${ip}:9081\"}[${metric_window}s])" "${m_end_time}")"
    max_threads_d="$(get_single_index "max_over_time(process_threads_count{instance=~\"${ip}:9091\"}[${metric_window}s])" "${m_end_time}")"
    maxNumofThread=$(( $(to_int "${max_threads_c}") + $(to_int "${max_threads_d}") ))
    maxCPULoad="$(get_single_index "max_over_time(sys_cpu_load{instance=~\"${ip}:9091\"}[${metric_window}s])" "${m_end_time}")"
    avgCPULoad="$(get_single_index "avg_over_time(sys_cpu_load{instance=~\"${ip}:9091\"}[${metric_window}s])" "${m_end_time}")"
    maxDiskIOOpsRead="$(get_single_index "sum(rate(disk_io_ops{instance=~\"${ip}:9091\",disk_id=~\"${DEFAULT_DISK_ID_REGEX}\",type=~\"read\"}[${metric_window}s]))" "${m_end_time}")"
    maxDiskIOOpsWrite="$(get_single_index "sum(rate(disk_io_ops{instance=~\"${ip}:9091\",disk_id=~\"${DEFAULT_DISK_ID_REGEX}\",type=~\"write\"}[${metric_window}s]))" "${m_end_time}")"
    maxDiskIOSizeRead="$(get_single_index "sum(rate(disk_io_size{instance=~\"${ip}:9091\",disk_id=~\"${DEFAULT_DISK_ID_REGEX}\",type=~\"read\"}[${metric_window}s]))" "${m_end_time}")"
    maxDiskIOSizeWrite="$(get_single_index "sum(rate(disk_io_size{instance=~\"${ip}:9091\",disk_id=~\"${DEFAULT_DISK_ID_REGEX}\",type=~\"write\"}[${metric_window}s]))" "${m_end_time}")"
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
    log "${ts_type} ${comp_type} compaction cost ${cost_time} s"
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
    path_is_safe "${backup_parent}" || die "refuse to use unexpected backup path: ${backup_parent}"
    sudo mkdir -p -- "${backup_parent}"
    path_is_safe "${backup_dir}" || die "refuse to use unexpected backup path: ${backup_dir}"
    sudo mkdir -p -- "${backup_dir}"

    sudo_safe_rm "${TEST_IOTDB_PATH}/data"
    path_is_safe "${TEST_IOTDB_PATH}" || die "refuse to move unexpected path: ${TEST_IOTDB_PATH}"
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
            die "unsupported compaction type: ${current_compaction_type}"
            ;;
    esac

    configure_compaction_mode "${current_compaction_type}" || die "failed to configure ${current_compaction_type}"
    collect_data_before
    start_iotdb
    m_start_time="$(date +%s)"
    sleep "${STARTUP_GRACE_SECONDS}"

    if ! wait_for_iotdb_ready "${ready_retries}" "${ready_interval_seconds}"; then
        log "IoTDB failed to start for ${current_compaction_type}, record failure result"
        record_startup_failure "${protocol_code}"
        stop_iotdb
        sleep "${STOP_WAIT_SECONDS}"
        cleanup_processes
        return 1
    fi

    sleep "${COMPACTION_INITIAL_WAIT_SECONDS}"
    if ! monitor_compaction_completion "${current_compaction_type}"; then
        case_failed=1
    fi

    stop_iotdb
    sleep "${STOP_WAIT_SECONDS}"
    cleanup_processes

    m_end_time="$(date +%s)"
    if ! collect_data_after; then
        log "failed to parse compaction result log for ${current_compaction_type}"
        case_failed=1
    fi
    collect_monitor_metrics "${TEST_IP}"
    insert_result_row "${protocol_code}"
    archive_compaction_artifacts "${current_compaction_type}"

    return "${case_failed}"
}

test_operation() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local compaction_case=""
    local operation_failed=0

    log "start compaction workflow for protocol ${protocol_code}, ts_type ${current_ts_type}"
    cleanup_processes
    set_env
    if ! set_protocol_class "${protocol_code}"; then
        log "invalid protocol configuration: ${protocol_code}"
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

mark_test_in_progress() {
    printf 'ontesting\n' > "${INIT_PATH}/test_type_file"
}

restore_test_type_file() {
    printf '%s\n' "${TEST_TYPE}" > "${INIT_PATH}/test_type_file"
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
    log "current commit ${commit_id} has not been tested, start compaction workflow"

    test_date_time="$(date +%Y%m%d%H%M%S)"
    for protocol in "${PROTOCOL_LIST[@]}"; do
        for ts in "${TS_LIST[@]}"; do
            if ! test_operation "${protocol}" "${ts}"; then
                task_failed=1
            fi
        done
    done

    log "compaction run ${test_date_time} finished"
    if [ "${task_failed}" -eq 0 ]; then
        update_task_status "done"
        mark_older_commits_skip
    else
        update_task_status "RError"
    fi
}

main "$@"
