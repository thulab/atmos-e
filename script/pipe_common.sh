#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "pipe_common.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "pipe_common.sh requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi

readonly TEST_TYPE="pipe_test"
readonly ACCOUNT="root"
readonly IOTDB_PW="TimechoDB@2021"

readonly INIT_PATH="/root/zk_test"
readonly ATMOS_PATH="${INIT_PATH}/atmos-e"
readonly BM_PATH="${INIT_PATH}/iot-benchmark"
readonly BM_REPOS_PATH="/nasdata/repository/iot-benchmark"
readonly REPOS_PATH="/nasdata/repository/master"
readonly BACKUP_PATH="/nasdata/repository/${TEST_TYPE}"

readonly TEST_INIT_PATH="/data/cluster/first-rest-test"
readonly TEST_IOTDB_PATH="${TEST_INIT_PATH}/apache-iotdb"
readonly TEST_BM_PATH="${TEST_INIT_PATH}/iot-benchmark"
readonly LOCAL_STAGE_ROOT="${INIT_PATH}/${TEST_TYPE}_stage"
readonly LOCAL_RESULT_ROOT="${LOCAL_STAGE_ROOT}/results"
readonly LOCAL_BACKUP_TMP="${LOCAL_STAGE_ROOT}/backup_tmp"

readonly MYSQLHOSTNAME="111.200.37.158"
readonly PORT="13306"
readonly USERNAME="iotdbatm"
readonly PASSWORD="${ATMOS_DB_PASSWORD:-}"
readonly DBNAME="QA_ATM"
readonly RESULT_TABLE_NAME="test_result_${TEST_TYPE}"
readonly TASK_TABLE_NAME="commit_history"

readonly METRIC_SERVER="172.20.70.11:9090"
readonly DEFAULT_DISK_ID="vdc"
readonly DISK_ID_REGEX="^${DEFAULT_DISK_ID}$"
# Older OpenSSH clients used in some test environments do not support `accept-new`.
readonly -a SSH_OPTIONS=(-o BatchMode=yes -o StrictHostKeyChecking=no)
readonly PIPE_NAME="test"
readonly ENABLE_BENCHMARK_VERSION_CHECK="${ENABLE_BENCHMARK_VERSION_CHECK:-1}"
readonly PIPE_CREATE_WARMUP_SECONDS=60
readonly BENCHMARK_WARMUP_SECONDS=10
readonly NODE_RESET_WAIT_SECONDS=120
readonly STARTUP_GRACE_SECONDS=5
readonly IOTDB_READY_RETRIES=50
readonly IOTDB_READY_INTERVAL_SECONDS=3
readonly MONITOR_TIMEOUT_SECONDS=3600
readonly MONITOR_POLL_INTERVAL_SECONDS=10
readonly REPLICATION_STABLE_SECONDS=600
readonly DEVICE_COUNT=50

readonly -a PROTOCOL_CLASS=(
    ""
    "org.apache.iotdb.consensus.simple.SimpleConsensus"
    "org.apache.iotdb.consensus.ratis.RatisConsensus"
    "org.apache.iotdb.consensus.iot.IoTConsensus"
    "org.apache.iotdb.consensus.iot.IoTConsensusV2"
)
readonly -a NODE_IPS=("172.20.31.45" "172.20.31.58")
readonly -a PIPE_PEERS=("172.20.31.58" "172.20.31.45")
readonly -a CONFIG_NODE_SEEDS=("172.20.31.45:10710" "172.20.31.58:10710")
readonly -a DATA_NODE_SEEDS=("172.20.31.45:10710" "172.20.31.58:10710")
readonly -a PIPE_CASES=(
    "223|tablemode"
    "223|common"
    "223|aligned"
    "224|aligned"
)

commit_id=""
author=""
commit_date_time=""
test_date_time=""
current_protocol_code=""
ts_type=""
start_time=""
end_time=""
cost_time=0
wait_time=0
min_point_num=1000000
m_start_time=0
m_end_time=0

declare -a fail_points
declare -a throughputs
declare -a latencies
declare -a num_of_seq_levels
declare -a num_of_unseq_levels
declare -a data_file_sizes
declare -a max_open_files
declare -a max_threads
declare -a wal_file_sizes
declare -a error_log_sizes
declare -a max_cpu_loads
declare -a avg_cpu_loads
declare -a max_disk_io_ops_read
declare -a max_disk_io_ops_write
declare -a max_disk_io_size_read
declare -a max_disk_io_size_write
declare -a node_a_counts
declare -a node_b_counts

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
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

check_password() {
    [ -n "${PASSWORD}" ] || die "ATMOS_DB_PASSWORD is not set"
}

ensure_runtime_dependencies() {
    local cmd=""

    for cmd in awk cp curl date du grep jq mkdir mysql rm scp sed ssh sudo tr; do
        require_command "${cmd}"
    done
}

path_is_safe() {
    local path="$1"

    [ -n "${path}" ] || return 1

    case "${path}" in
        "/"|"/data"|"/data/cluster"|"/nasdata"|".")
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
    path_is_safe "${path}" || die "Refuse to remove unexpected path: ${path}"
    rm -rf -- "${path}"
}

sudo_safe_rm() {
    local path="$1"

    [ -e "${path}" ] || return 0
    path_is_safe "${path}" || die "Refuse to remove unexpected path: ${path}"
    sudo rm -rf -- "${path}"
}

prepare_backup_directory() {
    local backup_dir="$1"
    local backup_parent="${backup_dir%/*}"

    sudo_safe_rm "${backup_dir}"
    path_is_safe "${backup_parent}" || die "Refuse to use unexpected backup path: ${backup_parent}"
    sudo mkdir -p -- "${backup_parent}"
    path_is_safe "${backup_dir}" || die "Refuse to use unexpected backup path: ${backup_dir}"
    sudo mkdir -p -- "${backup_dir}"
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

sql_maybe_quote() {
    local value="${1:-}"

    if [ -n "${value}" ]; then
        sql_quote "${value}"
    else
        printf 'NULL'
    fi
}

numeric_or_zero() {
    local value="${1:-0}"

    if [[ "${value}" =~ ^-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$ ]]; then
        printf '%s' "${value}"
    else
        printf '0'
    fi
}

query_next_commit() {
    local status_filter="$1"

    if [ "${status_filter}" = "retest" ]; then
        mysql_exec "SELECT commit_id, author, commit_date_time FROM ${TASK_TABLE_NAME} WHERE ${TEST_TYPE} = 'retest' ORDER BY commit_date_time DESC LIMIT 1"
    else
        mysql_exec "SELECT commit_id, author, commit_date_time FROM ${TASK_TABLE_NAME} WHERE ${TEST_TYPE} IS NULL ORDER BY commit_date_time DESC LIMIT 1"
    fi
}

fetch_next_commit() {
    local row=""
    local raw_commit_date_time=""

    row="$(query_next_commit "retest" 2>/dev/null || true)"
    if [ -z "${row}" ]; then
        row="$(query_next_commit "pending" 2>/dev/null || true)"
    fi
    [ -n "${row}" ] || return 1

    IFS=$'\t' read -r commit_id author raw_commit_date_time <<< "${row}"
    author="$(trim "${author}")"
    commit_date_time="$(normalize_datetime "${raw_commit_date_time}")"

    [ -n "${commit_id}" ] || return 1
    [ -n "${commit_date_time}" ] || die "Failed to parse commit_date_time"
}

update_task_status() {
    local status="$1"

    mysql_exec "UPDATE ${TASK_TABLE_NAME} SET ${TEST_TYPE} = $(sql_quote "${status}") WHERE commit_id = $(sql_quote "${commit_id}")"
}

mark_older_commits_skip() {
    mysql_exec "UPDATE ${TASK_TABLE_NAME} SET ${TEST_TYPE} = 'skip' WHERE ${TEST_TYPE} IS NULL AND commit_date_time < $(sql_quote "${commit_date_time}")"
}

mark_test_in_progress() {
    mkdir -p "${INIT_PATH}"
    printf 'ontesting\n' > "${INIT_PATH}/test_type_file"
}

restore_test_type_file() {
    mkdir -p "${INIT_PATH}"
    printf '%s\n' "${TEST_TYPE}" > "${INIT_PATH}/test_type_file"
}

check_benchmark_version() {
    local bm_new=""
    local bm_old=""

    [ -f "${BM_REPOS_PATH}/git.properties" ] || die "Missing benchmark git.properties: ${BM_REPOS_PATH}/git.properties"
    bm_new="$(awk -F= '/git.commit.id.abbrev/ {print $2}' "${BM_REPOS_PATH}/git.properties")"
    [ -n "${bm_new}" ] || die "Failed to read benchmark version"

    if [ -f "${BM_PATH}/git.properties" ]; then
        bm_old="$(awk -F= '/git.commit.id.abbrev/ {print $2}' "${BM_PATH}/git.properties")"
    fi

    if [ ! -d "${BM_PATH}" ] || [ "${bm_old}" != "${bm_new}" ]; then
        log "Sync benchmark directory to latest version"
        mkdir -p "${INIT_PATH}"
        safe_rm "${BM_PATH}"
        cp -rf "${BM_REPOS_PATH}" "${BM_PATH}"
    fi
}

remote_exec() {
    local host="$1"
    shift

    ssh -n "${SSH_OPTIONS[@]}" "${ACCOUNT}@${host}" "$@"
}

remote_start_in_dir() {
    local host="$1"
    local work_dir="$2"
    shift 2

    ssh "${SSH_OPTIONS[@]}" "${ACCOUNT}@${host}" sh -s -- "${work_dir}" "$@" <<'EOF'
work_dir="$1"
shift

cd "${work_dir}" || exit 1
nohup "$@" >/dev/null 2>&1 </dev/null &
EOF
}

build_remote_cli_command() {
    local host="$1"
    local dialect="$2"
    local sql="$3"
    local -a cmd=("${TEST_IOTDB_PATH}/sbin/start-cli.sh" -u root -pw "${IOTDB_PW}")
    local joined=""

    if [ "${dialect}" = "table" ]; then
        cmd+=(-sql_dialect table)
    fi
    cmd+=(-h "${host}" -p 6667 -e "${sql}")

    printf -v joined '%q ' "${cmd[@]}"
    printf '%s' "${joined% }"
}

remote_cli() {
    local host="$1"
    local dialect="$2"
    local sql="$3"
    local command=""

    command="$(build_remote_cli_command "${host}" "${dialect}" "${sql}")"
    remote_exec "${host}" "${command}"
}

remote_benchmark_running_count() {
    local host="$1"
    local count=""

    count="$(remote_exec "${host}" "command -v jps >/dev/null 2>&1 || { echo 0; exit 0; }; jps | awk '\$2 == \"App\" {count++} END {print count + 0}'" 2>/dev/null || true)"
    count="$(trim "${count}")"
    if [[ ! "${count}" =~ ^[0-9]+$ ]]; then
        count=0
    fi
    printf '%s\n' "${count}"
}

remote_collect_error_log_size() {
    local host="$1"

    ssh "${SSH_OPTIONS[@]}" "${ACCOUNT}@${host}" sh -s -- "${TEST_IOTDB_PATH}" <<'EOF'
test_iotdb_path="$1"
total=0

for log_file in \
    "${test_iotdb_path}/logs/log_datanode_error.log" \
    "${test_iotdb_path}/logs/log_confignode_error.log"; do
    if [ -f "${log_file}" ]; then
        size="$(du -sb "${log_file}" 2>/dev/null | awk 'NF { print $1; exit }')"
        size="${size:-0}"
        total=$((total + size))
    fi
done

printf '%s\n' "${total}"
EOF
}

bytes_to_gib() {
    awk -v value="${1:-0}" 'BEGIN { printf "%.2f\n", value / 1073741824 }'
}

to_int() {
    awk -v value="${1:-0}" 'BEGIN { printf "%d\n", value }'
}

get_single_index() {
    local query="$1"
    local end_time="$2"
    local index_value=""

    index_value="$(
        curl -G -s "http://${METRIC_SERVER}/api/v1/query" \
            --data-urlencode "query=${query}" \
            --data-urlencode "time=${end_time}" \
            | jq -r '.data.result[0].value[1] // 0'
    )"

    if [ "${index_value}" = "null" ] || [ -z "${index_value}" ]; then
        index_value=0
    fi

    printf '%s\n' "${index_value}"
}

init_case_state() {
    local idx=0
    local device=0

    current_protocol_code=""
    ts_type=""
    start_time=""
    end_time=""
    cost_time=0
    wait_time=0
    min_point_num=1000000
    m_start_time=0
    m_end_time=0

    for idx in 0 1; do
        fail_points[$idx]=0
        throughputs[$idx]=0
        latencies[$idx]=0
        num_of_seq_levels[$idx]=0
        num_of_unseq_levels[$idx]=0
        data_file_sizes[$idx]=0
        max_open_files[$idx]=0
        max_threads[$idx]=0
        wal_file_sizes[$idx]=0
        error_log_sizes[$idx]=0
        max_cpu_loads[$idx]=0
        avg_cpu_loads[$idx]=0
        max_disk_io_ops_read[$idx]=0
        max_disk_io_ops_write[$idx]=0
        max_disk_io_size_read[$idx]=0
        max_disk_io_size_write[$idx]=0
    done

    node_a_counts=()
    node_b_counts=()
    for ((device = 0; device < DEVICE_COUNT; device++)); do
        node_a_counts[$device]=0
        node_b_counts[$device]=0
    done
}

append_common_iotdb_properties() {
    local stage_dir="$1"
    local datanode_env="${stage_dir}/apache-iotdb/conf/datanode-env.sh"
    local confignode_env="${stage_dir}/apache-iotdb/conf/confignode-env.sh"
    local properties_file="${stage_dir}/apache-iotdb/conf/iotdb-system.properties"

    [ -f "${datanode_env}" ] || {
        log "Missing file: ${datanode_env}"
        return 1
    }
    [ -f "${confignode_env}" ] || {
        log "Missing file: ${confignode_env}"
        return 1
    }
    [ -f "${properties_file}" ] || {
        log "Missing file: ${properties_file}"
        return 1
    }

    sed -i 's/^#\?ON_HEAP_MEMORY=.*$/ON_HEAP_MEMORY="20G"/' "${datanode_env}" || return 1
    sed -i 's/^#\?ON_HEAP_MEMORY=.*$/ON_HEAP_MEMORY="6G"/' "${confignode_env}" || return 1

    cat >> "${properties_file}" <<EOF
query_timeout_threshold=6000000
enable_seq_space_compaction=false
enable_unseq_space_compaction=false
enable_cross_space_compaction=false
cluster_name=${TEST_TYPE}
enable_auto_create_schema=true
default_storage_group_level=2
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

append_protocol_properties() {
    local properties_file="$1"
    local protocol_code="$2"
    local config_node="${protocol_code:0:1}"
    local schema_region="${protocol_code:1:1}"
    local data_region="${protocol_code:2:1}"

    [ "${#protocol_code}" -eq 3 ] || {
        log "Invalid protocol code: ${protocol_code}"
        return 1
    }
    [ -n "${PROTOCOL_CLASS[${config_node}]:-}" ] || return 1
    [ -n "${PROTOCOL_CLASS[${schema_region}]:-}" ] || return 1
    [ -n "${PROTOCOL_CLASS[${data_region}]:-}" ] || return 1

    cat >> "${properties_file}" <<EOF
config_node_consensus_protocol_class=${PROTOCOL_CLASS[${config_node}]}
schema_region_consensus_protocol_class=${PROTOCOL_CLASS[${schema_region}]}
data_region_consensus_protocol_class=${PROTOCOL_CLASS[${data_region}]}
EOF
}

append_node_properties() {
    local properties_file="$1"
    local host="$2"
    local config_seed="$3"
    local data_seed="$4"

    cat >> "${properties_file}" <<EOF
dn_rpc_address=${host}
dn_internal_address=${host}
dn_seed_config_node=${data_seed}
cn_internal_address=${host}
cn_seed_config_node=${config_seed}
EOF
}

prepare_base_stage() {
    local protocol_code="$1"
    local base_dir="${LOCAL_STAGE_ROOT}/base"
    local source_path="${REPOS_PATH}/${commit_id}/apache-iotdb"
    local properties_file="${base_dir}/apache-iotdb/conf/iotdb-system.properties"

    [ -d "${source_path}" ] || {
        log "Missing compiled IoTDB directory: ${source_path}"
        return 1
    }
    [ -d "${BM_PATH}" ] || {
        log "Missing benchmark directory: ${BM_PATH}"
        return 1
    }

    safe_rm "${LOCAL_STAGE_ROOT}"
    mkdir -p "${base_dir}" || return 1
    cp -rf "${source_path}" "${base_dir}/apache-iotdb" || return 1
    cp -rf "${BM_PATH}" "${base_dir}/iot-benchmark" || return 1
    mkdir -p "${base_dir}/apache-iotdb/activation" || return 1

    append_common_iotdb_properties "${base_dir}" || return 1
    append_protocol_properties "${properties_file}" "${protocol_code}" || {
        log "Failed to append protocol settings: ${protocol_code}"
        return 1
    }
}

copy_pipe_benchmark_config() {
    local stage_dir="$1"
    local current_ts_type="$2"
    local host="$3"
    local config_source="${ATMOS_PATH}/conf/${TEST_TYPE}/${current_ts_type}/${host}"
    local config_target="${stage_dir}/iot-benchmark/conf/config.properties"

    [ -f "${config_source}" ] || {
        log "Missing benchmark config: ${config_source}"
        return 1
    }

    safe_rm "${config_target}"
    cp -rf "${config_source}" "${config_target}" || return 1
}

copy_pipe_license() {
    local stage_dir="$1"
    local host="$2"
    local license_source="${ATMOS_PATH}/conf/${TEST_TYPE}/${host}"
    local license_target="${stage_dir}/apache-iotdb/activation/license"

    [ -e "${license_source}" ] || {
        log "Missing license file: ${license_source}"
        return 1
    }

    safe_rm "${license_target}"
    cp -rf "${license_source}" "${license_target}" || return 1
}

prepare_node_stage() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local host="$3"
    local index="$4"
    local base_dir="${LOCAL_STAGE_ROOT}/base"
    local stage_dir="${LOCAL_STAGE_ROOT}/${host}"
    local properties_file="${stage_dir}/apache-iotdb/conf/iotdb-system.properties"

    safe_rm "${stage_dir}"
    mkdir -p "${stage_dir}" || return 1
    cp -rf "${base_dir}/." "${stage_dir}/" || return 1
    append_node_properties "${properties_file}" "${host}" "${CONFIG_NODE_SEEDS[$index]}" "${DATA_NODE_SEEDS[$index]}" || return 1
    copy_pipe_benchmark_config "${stage_dir}" "${current_ts_type}" "${host}" || return 1
    copy_pipe_license "${stage_dir}" "${host}" || return 1
    printf '%s\n' "${stage_dir}"
}

reset_remote_nodes() {
    local host=""

    for host in "${NODE_IPS[@]}"; do
        log "Reset runtime on ${host}"
        remote_exec "${host}" "command -v jps >/dev/null 2>&1 || exit 0; pids=\$(jps | awk '\$2 == \"App\" || \$2 == \"DataNode\" || \$2 == \"ConfigNode\" || \$2 == \"IoTDB\" {print \$1}'); if [ -n \"\$pids\" ]; then kill -9 \$pids; fi" >/dev/null 2>&1 || true
        remote_exec "${host}" "sync; echo 3 > /proc/sys/vm/drop_caches" >/dev/null 2>&1 || true
    done

    sleep "${NODE_RESET_WAIT_SECONDS}"
}

deploy_all_nodes() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local index=0
    local host=""
    local stage_dir=""

    prepare_base_stage "${protocol_code}" || return 1
    reset_remote_nodes

    for index in "${!NODE_IPS[@]}"; do
        host="${NODE_IPS[$index]}"
        stage_dir="$(prepare_node_stage "${protocol_code}" "${current_ts_type}" "${host}" "${index}")" || return 1
        log "Deploy payload to ${host}"
        remote_exec "${host}" "rm -rf ${TEST_INIT_PATH}; mkdir -p ${TEST_INIT_PATH}" || return 1
        scp "${SSH_OPTIONS[@]}" -r "${stage_dir}/." "${ACCOUNT}@${host}:${TEST_INIT_PATH}/" >/dev/null || return 1
    done
}

wait_for_remote_iotdb_ready() {
    local host="$1"
    local attempt=0
    local output=""

    for ((attempt = 1; attempt <= IOTDB_READY_RETRIES; attempt++)); do
        output="$(remote_exec "${host}" "${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${host} -p 6667 -e \"show cluster\"" 2>/dev/null || true)"
        if printf '%s\n' "${output}" | grep -Fq 'Total line number = 2'; then
            return 0
        fi
        sleep "${IOTDB_READY_INTERVAL_SECONDS}"
    done

    return 1
}

change_remote_root_password() {
    local host="$1"

    remote_exec "${host}" "${TEST_IOTDB_PATH}/sbin/start-cli.sh -h ${host} -p 6667 -e \"ALTER USER root SET PASSWORD '${IOTDB_PW}';\"" >/dev/null 2>&1
}

start_remote_node() {
    local host="$1"

    log "Start ConfigNode on ${host}"
    remote_start_in_dir "${host}" "${TEST_IOTDB_PATH}" ./sbin/start-confignode.sh || return 1
    sleep "${STARTUP_GRACE_SECONDS}"

    log "Start DataNode on ${host}"
    remote_start_in_dir "${host}" "${TEST_IOTDB_PATH}" ./sbin/start-datanode.sh -H "${TEST_IOTDB_PATH}/dn_dump.hprof" || return 1

    wait_for_remote_iotdb_ready "${host}" || return 1
    change_remote_root_password "${host}" || return 1
}

start_all_remote_nodes() {
    local host=""

    for host in "${NODE_IPS[@]}"; do
        start_remote_node "${host}" || {
            log "IoTDB is not ready on ${host}"
            return 1
        }
    done
}

stop_remote_node() {
    local host="$1"

    remote_exec "${host}" "[ -d ${TEST_IOTDB_PATH} ] && ${TEST_IOTDB_PATH}/sbin/stop-datanode.sh >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
    sleep "${STARTUP_GRACE_SECONDS}"
    remote_exec "${host}" "[ -d ${TEST_IOTDB_PATH} ] && ${TEST_IOTDB_PATH}/sbin/stop-confignode.sh >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
}

stop_all_remote_nodes() {
    local host=""

    for host in "${NODE_IPS[@]}"; do
        stop_remote_node "${host}"
    done
}

pipe_dialect() {
    local current_ts_type="$1"

    if [ "${current_ts_type}" = "tablemode" ]; then
        printf 'table\n'
    else
        printf 'tree\n'
    fi
}

build_pipe_create_sql() {
    local current_ts_type="$1"
    local sink_host="$2"
    local source_properties=""

    if [ "${current_ts_type}" = "tablemode" ]; then
        source_properties="'source.realtime.mode'='stream','source.realtime.enable'='true','source.forwarding-pipe-requests'='false','source.batch.enable'='true','source.history.enable'='true'"
    else
        source_properties="'source.pattern'='root','source.realtime.mode'='stream','source.realtime.enable'='true','source.forwarding-pipe-requests'='false','source.batch.enable'='true','source.history.enable'='true'"
    fi

    printf "create pipe %s with source (%s) with sink ('sink'='iotdb-thrift-sink','username'='root','password'='%s','sink.node-urls'='%s:6667');\n" \
        "${PIPE_NAME}" "${source_properties}" "${IOTDB_PW}" "${sink_host}"
}

create_all_pipes() {
    local current_ts_type="$1"
    local dialect=""
    local index=0
    local host=""
    local peer=""
    local create_sql=""
    local show_output=""
    local ready_count=0

    dialect="$(pipe_dialect "${current_ts_type}")"
    for index in "${!NODE_IPS[@]}"; do
        host="${NODE_IPS[$index]}"
        peer="${PIPE_PEERS[$index]}"
        create_sql="$(build_pipe_create_sql "${current_ts_type}" "${peer}")"

        log "Create pipe on ${host} -> ${peer}"
        remote_cli "${host}" "${dialect}" "${create_sql}" >/dev/null 2>&1 || continue
        remote_cli "${host}" "${dialect}" "start pipe ${PIPE_NAME};" >/dev/null 2>&1 || continue
        show_output="$(remote_cli "${host}" "${dialect}" "show pipes;" 2>/dev/null || true)"
        log "查看 ${show_output}"
        if printf '%s\n' "${show_output}" | grep -Eq 'Total line number = (1|2)'; then
            ready_count=$((ready_count + 1))
        fi
    done

    [ "${ready_count}" -eq "${#NODE_IPS[@]}" ]
}

start_remote_benchmarks() {
    local host=""
    local running_count=0

    for host in "${NODE_IPS[@]}"; do
        log "Start benchmark on ${host}"
        remote_start_in_dir "${host}" "${TEST_BM_PATH}" ./benchmark.sh || return 1
    done

    sleep 3
    for host in "${NODE_IPS[@]}"; do
        running_count="$(remote_benchmark_running_count "${host}")"
        if [ "${running_count}" -lt 1 ]; then
            log "Benchmark did not start on ${host}"
            return 1
        fi
    done
}

flush_remote_nodes() {
    local current_ts_type="$1"
    local dialect=""
    local host=""

    dialect="$(pipe_dialect "${current_ts_type}")"
    for host in "${NODE_IPS[@]}"; do
        remote_cli "${host}" "${dialect}" "flush;" >/dev/null 2>&1 || true
    done
}

query_node_device_counts() {
    local host="$1"
    local current_ts_type="$2"

    ssh "${SSH_OPTIONS[@]}" "${ACCOUNT}@${host}" sh -s -- "${TEST_IOTDB_PATH}" "${IOTDB_PW}" "${current_ts_type}" "${DEVICE_COUNT}" <<'EOF'
test_iotdb_path="$1"
iotdb_pw="$2"
current_ts_type="$3"
device_count="$4"
device=0

while [ "${device}" -lt "${device_count}" ]; do
    if [ "${current_ts_type}" = "tablemode" ]; then
        sql="select count(s_0) from test_g_0.table_0 where device_id = 'd_${device}'"
        output="$("${test_iotdb_path}/sbin/start-cli.sh" -u root -pw "${iotdb_pw}" -sql_dialect table -h 127.0.0.1 -p 6667 -e "${sql}" 2>/dev/null || true)"
    else
        sql="select count(s_0) from root.test.g_0.d_${device}"
        output="$("${test_iotdb_path}/sbin/start-cli.sh" -u root -pw "${iotdb_pw}" -h 127.0.0.1 -p 6667 -e "${sql}" 2>/dev/null || true)"
    fi

    value="$(printf '%s\n' "${output}" | sed -n '4p' | tr -d '|[:space:]')"
    if [ -z "${value}" ]; then
        value=0
    fi
    printf '%s\n' "${value}"
    device=$((device + 1))
done
EOF
}

store_counts_a() {
    local new_counts=("$@")
    local device=0
    local changed=1

    for ((device = 0; device < DEVICE_COUNT; device++)); do
        if [ "${node_a_counts[$device]:-0}" != "${new_counts[$device]:-0}" ]; then
            node_a_counts[$device]="${new_counts[$device]:-0}"
            changed=0
        fi
    done

    return "${changed}"
}

store_counts_b() {
    local new_counts=("$@")
    local device=0
    local changed=1

    for ((device = 0; device < DEVICE_COUNT; device++)); do
        if [ "${node_b_counts[$device]:-0}" != "${new_counts[$device]:-0}" ]; then
            node_b_counts[$device]="${new_counts[$device]:-0}"
            changed=0
        fi
    done

    return "${changed}"
}

calculate_min_point_num() {
    local device=0
    local min_value=1000000
    local current_value=0

    for ((device = 0; device < DEVICE_COUNT; device++)); do
        current_value="${node_a_counts[$device]:-0}"
        if [ "${min_value}" -ge "${current_value}" ]; then
            min_value="${current_value}"
        fi

        current_value="${node_b_counts[$device]:-0}"
        if [ "${min_value}" -ge "${current_value}" ]; then
            min_value="${current_value}"
        fi
    done

    printf '%s\n' "${min_value}"
}

monitor_pipe_case() {
    local start_epoch=0
    local last_update_epoch=0
    local now_epoch=0
    local bm_finished=0
    local changed=1
    local -a current_counts_a=()
    local -a current_counts_b=()

    start_epoch="$(datetime_to_epoch "${start_time}")"
    last_update_epoch="$(date +%s)"

    while true; do
        now_epoch="$(date +%s)"
        if [ $((now_epoch - start_epoch)) -ge "${MONITOR_TIMEOUT_SECONDS}" ]; then
            end_time="$(current_datetime)"
            cost_time=-1
            return 1
        fi

        bm_finished=0
        if [ "$(remote_benchmark_running_count "${NODE_IPS[0]}")" -eq 0 ]; then
            bm_finished=$((bm_finished + 1))
        fi
        if [ "$(remote_benchmark_running_count "${NODE_IPS[1]}")" -eq 0 ]; then
            bm_finished=$((bm_finished + 1))
        fi

        if [ "${bm_finished}" -lt "${#NODE_IPS[@]}" ]; then
            sleep "${MONITOR_POLL_INTERVAL_SECONDS}"
            continue
        fi

        flush_remote_nodes "${ts_type}"

        mapfile -t current_counts_a < <(query_node_device_counts "${NODE_IPS[0]}" "${ts_type}")
        mapfile -t current_counts_b < <(query_node_device_counts "${NODE_IPS[1]}" "${ts_type}")

        changed=1
        if store_counts_a "${current_counts_a[@]}"; then
            changed=0
        fi
        if store_counts_b "${current_counts_b[@]}"; then
            changed=0
        fi

        if [ "${changed}" -eq 0 ]; then
            last_update_epoch="${now_epoch}"
        fi

        if [ $((now_epoch - last_update_epoch)) -ge "${REPLICATION_STABLE_SECONDS}" ]; then
            end_time="$(current_datetime)"
            cost_time=$((last_update_epoch - start_epoch))
            min_point_num="$(calculate_min_point_num)"
            return 0
        fi

        sleep "${MONITOR_POLL_INTERVAL_SECONDS}"
    done
}

collect_node_metrics() {
    local index="$1"
    local host="$2"
    local metric_window=0
    local max_threads_cn=0
    local max_threads_dn=0
    local error_log_size=0

    if [ "${m_start_time}" -le 0 ]; then
        m_start_time="$(date +%s)"
    fi
    if [ "${m_end_time}" -le 0 ] || [ "${m_end_time}" -lt "${m_start_time}" ]; then
        m_end_time="$(date +%s)"
    fi

    metric_window=$((m_end_time - m_start_time))
    if [ "${metric_window}" -le 0 ]; then
        metric_window=1
    fi

    data_file_sizes[$index]="$(bytes_to_gib "$(get_single_index "sum(file_global_size{instance=~\"${host}:9091\"})" "${m_end_time}")")"
    num_of_seq_levels[$index]="$(get_single_index "sum(file_global_count{instance=~\"${host}:9091\",name=\"seq\"})" "${m_end_time}")"
    num_of_unseq_levels[$index]="$(get_single_index "sum(file_global_count{instance=~\"${host}:9091\",name=\"unseq\"})" "${m_end_time}")"

    max_threads_cn="$(get_single_index "max_over_time(process_threads_count{instance=~\"${host}:9081\"}[${metric_window}s])" "${m_end_time}")"
    max_threads_dn="$(get_single_index "max_over_time(process_threads_count{instance=~\"${host}:9091\"}[${metric_window}s])" "${m_end_time}")"
    max_threads[$index]=$(( $(to_int "${max_threads_cn}") + $(to_int "${max_threads_dn}") ))
    max_open_files[$index]="$(get_single_index "max_over_time(file_count{instance=~\"${host}:9091\",name=\"open_file_handlers\"}[${metric_window}s])" "${m_end_time}")"
    wal_file_sizes[$index]="$(bytes_to_gib "$(get_single_index "max_over_time(file_size{instance=~\"${host}:9091\",name=~\"wal\"}[${metric_window}s])" "${m_end_time}")")"

    error_log_size="$(remote_collect_error_log_size "${host}" 2>/dev/null || true)"
    if [[ ! "${error_log_size}" =~ ^[0-9]+$ ]]; then
        error_log_size=0
    fi
    error_log_sizes[$index]="${error_log_size}"

    max_cpu_loads[$index]="$(get_single_index "max_over_time(sys_cpu_load{instance=~\"${host}:9091\"}[${metric_window}s])" "${m_end_time}")"
    avg_cpu_loads[$index]="$(get_single_index "avg_over_time(sys_cpu_load{instance=~\"${host}:9091\"}[${metric_window}s])" "${m_end_time}")"
    max_disk_io_ops_read[$index]="$(get_single_index "sum(rate(disk_io_ops{instance=~\"${host}:9091\",disk_id=~\"${DISK_ID_REGEX}\",type=~\"read\"}[${metric_window}s]))" "${m_end_time}")"
    max_disk_io_ops_write[$index]="$(get_single_index "sum(rate(disk_io_ops{instance=~\"${host}:9091\",disk_id=~\"${DISK_ID_REGEX}\",type=~\"write\"}[${metric_window}s]))" "${m_end_time}")"
    max_disk_io_size_read[$index]="$(get_single_index "sum(rate(disk_io_size{instance=~\"${host}:9091\",disk_id=~\"${DISK_ID_REGEX}\",type=~\"read\"}[${metric_window}s]))" "${m_end_time}")"
    max_disk_io_size_write[$index]="$(get_single_index "sum(rate(disk_io_size{instance=~\"${host}:9091\",disk_id=~\"${DISK_ID_REGEX}\",type=~\"write\"}[${metric_window}s]))" "${m_end_time}")"
}

collect_all_monitor_data() {
    collect_node_metrics 0 "${NODE_IPS[0]}"
    collect_node_metrics 1 "${NODE_IPS[1]}"
}

find_first_result_csv() {
    local result_dir="$1"
    local had_nullglob=0
    local files=()

    if shopt -q nullglob; then
        had_nullglob=1
    else
        shopt -s nullglob
    fi

    files=("${result_dir}"/*result.csv)

    if [ "${had_nullglob}" -eq 0 ]; then
        shopt -u nullglob
    fi

    if [ "${#files[@]}" -gt 0 ]; then
        printf '%s\n' "${files[0]}"
    fi
}

parse_ingestion_result() {
    local csv_file="$1"
    local index="$2"
    local throughput_line=""
    local latency_line=""
    local ok_operation=0
    local ok_point=0
    local fail_operation=0
    local fail_point=0
    local throughput_value=0
    local latency_value=0
    local min_value=0
    local p10=0
    local p25=0
    local median=0
    local p75=0
    local p90=0
    local p95=0
    local p99=0
    local p999=0
    local max_value=0

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

    IFS=$'\t' read -r ok_operation ok_point fail_operation fail_point throughput_value <<< "${throughput_line}"
    IFS=$'\t' read -r latency_value min_value p10 p25 median p75 p90 p95 p99 p999 max_value <<< "${latency_line}"

    fail_points[$index]="${fail_point:-0}"
    throughputs[$index]="${throughput_value:-0}"
    latencies[$index]="${latency_value:-0}"
}

collect_node_result() {
    local host="$1"
    local index="$2"
    local node_result_dir="${LOCAL_RESULT_ROOT}/${host}"
    local csv_file=""

    mkdir -p "${node_result_dir}" || return 1
    scp "${SSH_OPTIONS[@]}" -r "${ACCOUNT}@${host}:${TEST_BM_PATH}/data/csvOutput/*result.csv" "${node_result_dir}/" >/dev/null 2>&1 || true
    csv_file="$(find_first_result_csv "${node_result_dir}" || true)"
    [ -n "${csv_file}" ] || return 0
    parse_ingestion_result "${csv_file}" "${index}" || return 1
}

collect_all_results() {
    safe_rm "${LOCAL_RESULT_ROOT}"
    mkdir -p "${LOCAL_RESULT_ROOT}" || return 1
    collect_node_result "${NODE_IPS[0]}" 0 || true
    collect_node_result "${NODE_IPS[1]}" 1 || true
}

ensure_case_times_initialized() {
    local now_time=""

    now_time="$(current_datetime)"
    if [ -z "${start_time}" ]; then
        start_time="${now_time}"
    fi
    if [ -z "${end_time}" ]; then
        end_time="${now_time}"
    fi
    if [ "${m_start_time}" -le 0 ]; then
        m_start_time="$(date +%s)"
    fi
    if [ "${m_end_time}" -le 0 ] || [ "${m_end_time}" -lt "${m_start_time}" ]; then
        m_end_time="$(date +%s)"
    fi
}

insert_result_row() {
    local insert_sql=""

    ensure_case_times_initialized
    insert_sql="
INSERT INTO ${RESULT_TABLE_NAME} (
    commit_date_time,test_date_time,commit_id,author,ts_type,start_time,end_time,cost_time,wait_time,
    failPointA,throughputA,LatencyA,numOfSe0LevelA,numOfUnse0LevelA,dataFileSizeA,maxNumofOpenFilesA,maxNumofThreadA,walFileSizeA,avgCPULoadA,maxCPULoadA,maxDiskIOSizeReadA,maxDiskIOSizeWriteA,maxDiskIOOpsReadA,maxDiskIOOpsWriteA,errorLogSizeA,
    failPointB,throughputB,LatencyB,numOfSe0LevelB,numOfUnse0LevelB,dataFileSizeB,maxNumofOpenFilesB,maxNumofThreadB,walFileSizeB,avgCPULoadB,maxCPULoadB,maxDiskIOSizeReadB,maxDiskIOSizeWriteB,maxDiskIOOpsReadB,maxDiskIOOpsWriteB,errorLogSizeB,
    minPointNum,remark
) VALUES (
    ${commit_date_time},
    ${test_date_time},
    $(sql_quote "${commit_id}"),
    $(sql_quote "${author}"),
    $(sql_quote "${ts_type}"),
    $(sql_maybe_quote "${start_time}"),
    $(sql_maybe_quote "${end_time}"),
    $(numeric_or_zero "${cost_time}"),
    $(numeric_or_zero "${wait_time}"),
    $(numeric_or_zero "${fail_points[0]:-0}"),
    $(numeric_or_zero "${throughputs[0]:-0}"),
    $(numeric_or_zero "${latencies[0]:-0}"),
    $(numeric_or_zero "${num_of_seq_levels[0]:-0}"),
    $(numeric_or_zero "${num_of_unseq_levels[0]:-0}"),
    $(numeric_or_zero "${data_file_sizes[0]:-0}"),
    $(numeric_or_zero "${max_open_files[0]:-0}"),
    $(numeric_or_zero "${max_threads[0]:-0}"),
    $(numeric_or_zero "${wal_file_sizes[0]:-0}"),
    $(numeric_or_zero "${avg_cpu_loads[0]:-0}"),
    $(numeric_or_zero "${max_cpu_loads[0]:-0}"),
    $(numeric_or_zero "${max_disk_io_size_read[0]:-0}"),
    $(numeric_or_zero "${max_disk_io_size_write[0]:-0}"),
    $(numeric_or_zero "${max_disk_io_ops_read[0]:-0}"),
    $(numeric_or_zero "${max_disk_io_ops_write[0]:-0}"),
    $(numeric_or_zero "${error_log_sizes[0]:-0}"),
    $(numeric_or_zero "${fail_points[1]:-0}"),
    $(numeric_or_zero "${throughputs[1]:-0}"),
    $(numeric_or_zero "${latencies[1]:-0}"),
    $(numeric_or_zero "${num_of_seq_levels[1]:-0}"),
    $(numeric_or_zero "${num_of_unseq_levels[1]:-0}"),
    $(numeric_or_zero "${data_file_sizes[1]:-0}"),
    $(numeric_or_zero "${max_open_files[1]:-0}"),
    $(numeric_or_zero "${max_threads[1]:-0}"),
    $(numeric_or_zero "${wal_file_sizes[1]:-0}"),
    $(numeric_or_zero "${avg_cpu_loads[1]:-0}"),
    $(numeric_or_zero "${max_cpu_loads[1]:-0}"),
    $(numeric_or_zero "${max_disk_io_size_read[1]:-0}"),
    $(numeric_or_zero "${max_disk_io_size_write[1]:-0}"),
    $(numeric_or_zero "${max_disk_io_ops_read[1]:-0}"),
    $(numeric_or_zero "${max_disk_io_ops_write[1]:-0}"),
    $(numeric_or_zero "${error_log_sizes[1]:-0}"),
    $(numeric_or_zero "${min_point_num}"),
    $(sql_quote "${current_protocol_code}")
)"

    mysql_exec "${insert_sql}"
}

backup_case_data() {
    local backup_dir="${BACKUP_PATH}/${ts_type}/${commit_date_time}_${commit_id}_${current_protocol_code}"
    local host=""
    local host_tmp_dir=""

    prepare_backup_directory "${backup_dir}"
    safe_rm "${LOCAL_BACKUP_TMP}"
    mkdir -p "${LOCAL_BACKUP_TMP}" || return 1

    for host in "${NODE_IPS[@]}"; do
        host_tmp_dir="${LOCAL_BACKUP_TMP}/${host}"
        mkdir -p "${host_tmp_dir}" || return 1
        sudo mkdir -p -- "${backup_dir}/${host}" || return 1

        remote_exec "${host}" "rm -rf ${TEST_IOTDB_PATH}/data" >/dev/null 2>&1 || true
        scp "${SSH_OPTIONS[@]}" -r "${ACCOUNT}@${host}:${TEST_IOTDB_PATH}/" "${host_tmp_dir}/" >/dev/null 2>&1 || {
            log "Skip backup copy from ${host}"
            continue
        }
        sudo cp -rf "${host_tmp_dir}/." "${backup_dir}/${host}/" || return 1
    done

    if [ -d "${LOCAL_RESULT_ROOT}" ]; then
        sudo cp -rf "${LOCAL_RESULT_ROOT}" "${backup_dir}/results" || return 1
    fi
}

run_pipe_case() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local case_failed=0

    init_case_state
    current_protocol_code="${protocol_code}"
    ts_type="${current_ts_type}"

    log "Start pipe case: protocol=${protocol_code}, ts_type=${current_ts_type}"

    if ! deploy_all_nodes "${protocol_code}" "${current_ts_type}"; then
        case_failed=1
        cost_time=-5
    fi

    if [ "${case_failed}" -eq 0 ] && ! start_all_remote_nodes; then
        case_failed=1
        cost_time=-5
    fi

    if [ "${case_failed}" -eq 0 ] && ! create_all_pipes "${current_ts_type}"; then
        log "Pipe is not ready for protocol=${protocol_code}, ts_type=${current_ts_type}"
        case_failed=1
        cost_time=-5
    fi

    if [ "${case_failed}" -eq 0 ]; then
        sleep "${PIPE_CREATE_WARMUP_SECONDS}"
        start_time="$(current_datetime)"
        m_start_time="$(date +%s)"

        if ! start_remote_benchmarks; then
            case_failed=1
            cost_time=-5
        else
            sleep "${BENCHMARK_WARMUP_SECONDS}"
            if ! monitor_pipe_case; then
                case_failed=1
            fi
        fi
    else
        start_time="$(current_datetime)"
        end_time="${start_time}"
    fi

    m_end_time="$(date +%s)"
    if [ "${m_start_time}" -gt 0 ]; then
        collect_all_monitor_data || true
        collect_all_results || true
    fi

    if ! insert_result_row; then
        case_failed=1
    fi

    stop_all_remote_nodes
    backup_case_data || true

    return "${case_failed}"
}

main() {
    local case_spec=""
    local protocol_code=""
    local current_ts_type=""
    local task_failed=0

    trap restore_test_type_file EXIT

    ensure_runtime_dependencies
    check_password
    if [ "${ENABLE_BENCHMARK_VERSION_CHECK}" = "1" ]; then
        check_benchmark_version
    fi

    mark_test_in_progress
    if ! fetch_next_commit; then
        sleep 60
        return 0
    fi

    update_task_status "ontesting"
    log "Start pipe_test workflow for commit ${commit_id}"

    test_date_time="$(date +%Y%m%d%H%M%S)"
    for case_spec in "${PIPE_CASES[@]}"; do
        IFS='|' read -r protocol_code current_ts_type <<< "${case_spec}"
        if ! run_pipe_case "${protocol_code}" "${current_ts_type}"; then
            task_failed=1
        fi
    done

    log "pipe_test ${test_date_time} finished"
    if [ "${task_failed}" -eq 0 ]; then
        update_task_status "done"
        mark_older_commits_skip
    else
        update_task_status "RError"
    fi
}
