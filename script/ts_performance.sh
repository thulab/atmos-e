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

readonly INIT_PATH="/root/zk_test"
readonly ATMOS_PATH="${INIT_PATH}/atmos-e"
readonly DATASET_PATH="/nasdata/${TEST_TYPE}/DataSet"
readonly BACKUP_PATH="/nasdata/repository/${TEST_TYPE}"
readonly REPOS_PATH="/nasdata/repository/master"

readonly TEST_INIT_PATH="/data/qa"
readonly TEST_IOTDB_PATH="${TEST_INIT_PATH}/apache-iotdb"
readonly LIVE_LOG_DIR="${TEST_IOTDB_PATH}/tools/testlog"
readonly LIVE_LOG_FILE="${LIVE_LOG_DIR}/log.txt"
readonly EXPORT_DATA_DIR="${TEST_IOTDB_PATH}/tools/data"
readonly EXPORT_SEQUENCE_DIR="${EXPORT_DATA_DIR}/datanode/data/sequence"

readonly TABLEMODE_DATABASE="test_g_0"
readonly TABLEMODE_TABLE="table_0"
readonly TABLEMODE_SCHEMA_FILE="${ATMOS_PATH}/conf/${TEST_TYPE}/metadata/dump_test_g_0.sql"

readonly -a PROTOCOL_CLASS=(
    ""
    "org.apache.iotdb.consensus.simple.SimpleConsensus"
    "org.apache.iotdb.consensus.ratis.RatisConsensus"
    "org.apache.iotdb.consensus.iot.IoTConsensus"
    "org.apache.iotdb.consensus.iot.IoTConsensusV2"
)
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

readonly MYSQLHOSTNAME="111.200.37.158"
readonly PORT="13306"
readonly USERNAME="iotdbatm"
readonly PASSWORD="${ATMOS_DB_PASSWORD:-}"
readonly DBNAME="QA_ATM"
readonly TABLENAME="test_result_${TEST_TYPE}"
readonly TASK_TABLENAME="commit_history"

readonly MONITOR_TIMEOUT_SECONDS=7200
readonly MONITOR_POLL_INTERVAL_SECONDS=10
readonly IOTDB_READY_RETRIES=10
readonly IOTDB_READY_INTERVAL_SECONDS=5
readonly STARTUP_GRACE_SECONDS=10
readonly STOP_WAIT_SECONDS=30
readonly OPERATION_WARMUP_SECONDS=30

commit_id=""
author=""
commit_date_time=""
test_date_time=""
ts_type=""
data_type=""

start_time=""
end_time=""
cost_time=0
numOfSe0Level_before=0
numOfSe0Level_after=0
numOfUnse0Level_before=0
numOfUnse0Level_after=0
ts_dataSize=0
ts_numOfPoints=0
ts_rate=0
dataFileSize_before=0
dataFileSize_after=0
maxNumofOpenFiles=0
maxNumofThread=0
errorLogSize=0

operation_pid=0
export_properties_applied=0

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

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "缺少依赖命令: $1"
}

check_password() {
    if [ -z "${PASSWORD}" ]; then
        die "ATMOS_DB_PASSWORD 未设置，无法连接 MySQL"
    fi
}

ensure_runtime_dependencies() {
    local cmd=""
    for cmd in awk cp date du find grep jps kill lsof mkdir mv mysql pstree rm sed sudo tr wc; do
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

bytes_to_gib() {
    awk -v value="${1:-0}" 'BEGIN { printf "%.2f\n", value / 1073741824 }'
}

directory_size_gib() {
    local path="$1"
    local size_bytes=0

    if [ ! -d "${path}" ]; then
        printf '0\n'
        return 0
    fi

    size_bytes="$(du -sb "${path}" 2>/dev/null | awk 'NR == 1 { print $1 }')"
    size_bytes="${size_bytes:-0}"
    bytes_to_gib "${size_bytes}"
}

count_tsfiles() {
    local path="$1"

    if [ ! -d "${path}" ]; then
        printf '0\n'
        return 0
    fi

    find "${path}" -type f -name '*.tsfile' | wc -l | awk '{print $1}'
}

collect_error_log_size() {
    local datanode_log="${TEST_IOTDB_PATH}/logs/log_datanode_error.log"
    local confignode_log="${TEST_IOTDB_PATH}/logs/log_confignode_error.log"
    local datanode_size=0
    local confignode_size=0

    datanode_size="$(du -sb "${datanode_log}" 2>/dev/null | awk 'NR == 1 { print $1 }')"
    confignode_size="$(du -sb "${confignode_log}" 2>/dev/null | awk 'NR == 1 { print $1 }')"
    datanode_size="${datanode_size:-0}"
    confignode_size="${confignode_size:-0}"
    printf '%s\n' "$((datanode_size + confignode_size))"
}

reset_phase_metrics() {
    start_time=""
    end_time=""
    cost_time=0
    numOfSe0Level_before=0
    numOfSe0Level_after=0
    numOfUnse0Level_before=0
    numOfUnse0Level_after=0
    ts_dataSize=0
    ts_numOfPoints=0
    ts_rate=0
    dataFileSize_before=0
    dataFileSize_after=0
    maxNumofOpenFiles=0
    maxNumofThread=0
    errorLogSize=0
}

collect_data_stats() {
    local base_path="$1"
    local stage="$2"
    local data_root="${base_path}/data"
    local seq_count=0
    local unseq_count=0
    local total_size=0

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
        errorLogSize="$(collect_error_log_size)"
    fi
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
    stop_active_operation
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
    mkdir -p "${LIVE_LOG_DIR}"
}

modify_iotdb_config() {
    local datanode_env="${TEST_IOTDB_PATH}/conf/datanode-env.sh"
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"

    [ -f "${datanode_env}" ] || die "缺少配置文件: ${datanode_env}"
    [ -f "${properties_file}" ] || die "缺少配置文件: ${properties_file}"

    sed -i 's/^#\?ON_HEAP_MEMORY=.*$/ON_HEAP_MEMORY="20G"/' "${datanode_env}"

    cat >> "${properties_file}" <<EOF
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
EOF
}

append_export_properties() {
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"

    [ -f "${properties_file}" ] || die "缺少配置文件: ${properties_file}"
    cat >> "${properties_file}" <<EOF
max_deduplicated_path_num=60000000
query_timeout_threshold=60000000
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

count_open_files_for_process() {
    local pname="$1"
    local pid=""

    pid="$(jps | awk -v pname="${pname}" '$2 == pname {print $1; exit}')"
    if [ -z "${pid}" ]; then
        printf '0\n'
        return 0
    fi

    lsof -p "${pid}" 2>/dev/null | wc -l | awk '{print $1}'
}

count_threads_for_process() {
    local pname="$1"
    local pid=""

    pid="$(jps | awk -v pname="${pname}" '$2 == pname {print $1; exit}')"
    if [ -z "${pid}" ]; then
        printf '0\n'
        return 0
    fi

    pstree -p "${pid}" 2>/dev/null | wc -l | awk '{print $1}'
}

sample_process_usage() {
    local pname=""
    local open_total=0
    local thread_total=0
    local open_count=0
    local thread_count=0

    for pname in DataNode ConfigNode IoTDB; do
        open_count="$(count_open_files_for_process "${pname}")"
        thread_count="$(count_threads_for_process "${pname}")"
        open_total=$((open_total + open_count))
        thread_total=$((thread_total + thread_count))
    done

    if [ "${open_total}" -gt "${maxNumofOpenFiles}" ]; then
        maxNumofOpenFiles="${open_total}"
    fi
    if [ "${thread_total}" -gt "${maxNumofThread}" ]; then
        maxNumofThread="${thread_total}"
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
        sample_process_usage

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

    ts_numOfPoints="$(query_point_count)"
    stop_iotdb
    sleep "${STOP_WAIT_SECONDS}"
    cleanup_processes

    collect_data_stats "${after_base}" "after"
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
    modify_iotdb_config

    if ! set_protocol_class "${protocol_code}"; then
        log "协议配置无效: ${protocol_code}"
        return 1
    fi

    if ! run_phase "load-tsfile" "${DATASET_PATH}/${data_type}/${ts_type}" "${TEST_IOTDB_PATH}" 0; then
        case_failed=1
    fi
    if ! run_phase "export-tsfile" "${TEST_IOTDB_PATH}" "${TEST_IOTDB_PATH}/tools" 1; then
        case_failed=1
    fi
    if ! run_phase "export-csv" "${TEST_IOTDB_PATH}" "${TEST_IOTDB_PATH}/tools" 1; then
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
