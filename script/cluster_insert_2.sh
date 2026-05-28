#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_TYPE="cluster_insert_2"
readonly TEST_IP="172.20.70.22"
readonly METRIC_SERVER="172.20.70.11:9090"
readonly MONITOR_TIMEOUT_SECONDS=30000
readonly MONITOR_POLL_INTERVAL_SECONDS=30

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/runtime_common.sh
source "${SCRIPT_DIR}/runtime_common.sh"

readonly ACCOUNT="root"
readonly IOTDB_PW="TimechoDB@2021"
readonly TEST_PATH="/data/cluster/first-rest-test"
readonly TEST_DATANODE_PATH="${TEST_PATH}/DN/apache-iotdb"
readonly TEST_CONFIGNODE_PATH="${TEST_PATH}/CN/apache-iotdb"
readonly BUCKUP_PATH="${BACKUP_PATH}"
readonly TABLENAME="test_result_cluster_insert_2"
readonly BENCHMARK_RESULT_PATH="${BM_PATH}/TestResult/csvOutput"

readonly CLUSTER_CONFIG_COUNT=3
readonly CLUSTER_DATA_COUNT=5
readonly CLUSTER_BENCHMARK_COUNT=1
readonly CLUSTER_NAME="IoTDB-Enterprise-20"
readonly DISK_ID_PATTERN="vdc"

readonly -a IP_LIST=(
    ""
    "172.20.70.22"
    "172.20.70.23"
    "172.20.70.24"
    "172.20.70.7"
    "172.20.70.8"
    "172.20.70.9"
)
readonly -a DATA_NODE_IP_LIST=(
    ""
    "172.20.70.22"
    "172.20.70.23"
    "172.20.70.24"
    "172.20.70.7"
    "172.20.70.8"
)
readonly -a CONFIG_NODE_IP_LIST=(
    ""
    "172.20.70.22"
    "172.20.70.23"
    "172.20.70.24"
    "172.20.70.7"
    "172.20.70.8"
)
readonly -a BENCHMARK_IP_LIST=(
    ""
    "172.20.70.9"
)
readonly -a CONFIG_SCHEMA_REPLICATION_FACTOR=("" 3 3 3 3 3 3)
readonly -a CONFIG_DATA_REPLICATION_FACTOR=("" 3 3 3 3 3 3)
readonly -a CONFIG_NODE_CONFIG_NODES=(
    ""
    "172.20.70.22:10710"
    "172.20.70.22:10710"
    "172.20.70.22:10710"
)
readonly -a DATA_NODE_CONFIG_NODES=(
    ""
    "172.20.70.22:10710"
    "172.20.70.23:10710"
    "172.20.70.24:10710"
)

ensure_runtime_dependencies() {
    local cmd=""

    ensure_base_runtime_dependencies
    for cmd in scp ssh; do
        require_command "${cmd}"
    done
}

remote_exec() {
    local host="$1"
    shift

    ssh "${ACCOUNT}@${host}" "$@"
}

init_items() {
    init_common_items
    test_date_time=0
    ts_type=""
    maxCPULoad=0
    avgCPULoad=0
    maxDiskIOOpsRead=0
    maxDiskIOOpsWrite=0
    maxDiskIOSizeRead=0
    maxDiskIOSizeWrite=0
}

set_env() {
    local source_path="${REPOS_PATH}/${commit_id}/apache-iotdb"

    [ -d "${source_path}" ] || die "缺少待测版本目录: ${source_path}"

    # 集群测试目录位于 /data/cluster 下，沿用脚本原有清理方式。
    rm -rf -- "${TEST_PATH}"
    mkdir -p "${TEST_CONFIGNODE_PATH}" "${TEST_DATANODE_PATH}" "${TEST_CONFIGNODE_PATH}/activation"

    cp -rf "${source_path}/." "${TEST_CONFIGNODE_PATH}/"
    cp -rf "${source_path}/." "${TEST_DATANODE_PATH}/"
    copy_if_exists "${ATMOS_PATH}/conf/${TEST_TYPE}/license" "${TEST_CONFIGNODE_PATH}/activation/" "license"
    copy_if_exists "${ATMOS_PATH}/conf/${TEST_TYPE}/env" "${TEST_CONFIGNODE_PATH}/.env" "env"
}

modify_iotdb_config() {
    local datanode_env="${TEST_DATANODE_PATH}/conf/datanode-env.sh"
    local confignode_env="${TEST_CONFIGNODE_PATH}/conf/confignode-env.sh"
    local datanode_properties="${TEST_DATANODE_PATH}/conf/iotdb-system.properties"
    local confignode_properties="${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"

    [ -f "${datanode_env}" ] || die "缺少配置文件: ${datanode_env}"
    [ -f "${confignode_env}" ] || die "缺少配置文件: ${confignode_env}"
    [ -f "${datanode_properties}" ] || die "缺少配置文件: ${datanode_properties}"
    [ -f "${confignode_properties}" ] || die "缺少配置文件: ${confignode_properties}"

    sed -i 's/^#\?ON_HEAP_MEMORY=.*$/ON_HEAP_MEMORY="20G"/' "${datanode_env}"
    sed -i 's/^#\?ON_HEAP_MEMORY=.*$/ON_HEAP_MEMORY="6G"/' "${confignode_env}"

    cat >> "${datanode_properties}" <<EOF
enable_seq_space_compaction=false
enable_unseq_space_compaction=false
enable_cross_space_compaction=false
cluster_name=${CLUSTER_NAME}
dn_enable_metric=true
dn_enable_performance_stat=true
dn_metric_reporter_list=PROMETHEUS
dn_metric_level=ALL
dn_metric_prometheus_reporter_port=9091
EOF

    cat >> "${confignode_properties}" <<EOF
cluster_name=${CLUSTER_NAME}
cn_enable_metric=true
cn_enable_performance_stat=true
cn_metric_reporter_list=PROMETHEUS
cn_metric_level=ALL
cn_metric_prometheus_reporter_port=9081
EOF
}

set_protocol_class() {
    local config_node="$1"
    local schema_region="$2"
    local data_region="$3"
    local datanode_properties="${TEST_DATANODE_PATH}/conf/iotdb-system.properties"
    local confignode_properties="${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"

    [ -n "${PROTOCOL_CLASS[${config_node}]:-}" ] || die "未知 config consensus 类型: ${config_node}"
    [ -n "${PROTOCOL_CLASS[${schema_region}]:-}" ] || die "未知 schema consensus 类型: ${schema_region}"
    [ -n "${PROTOCOL_CLASS[${data_region}]:-}" ] || die "未知 data consensus 类型: ${data_region}"

    cat >> "${confignode_properties}" <<EOF
config_node_consensus_protocol_class=${PROTOCOL_CLASS[${config_node}]}
schema_region_consensus_protocol_class=${PROTOCOL_CLASS[${schema_region}]}
data_region_consensus_protocol_class=${PROTOCOL_CLASS[${data_region}]}
EOF

    cat >> "${datanode_properties}" <<EOF
config_node_consensus_protocol_class=${PROTOCOL_CLASS[${config_node}]}
schema_region_consensus_protocol_class=${PROTOCOL_CLASS[${schema_region}]}
data_region_consensus_protocol_class=${PROTOCOL_CLASS[${data_region}]}
EOF
}

apply_protocol_settings() {
    local protocol_code="$1"

    case "${protocol_code}" in
        111) set_protocol_class 1 1 1 ;;
        211) set_protocol_class 2 1 1 ;;
        222) set_protocol_class 2 2 2 ;;
        223) set_protocol_class 2 2 3 ;;
        224) set_protocol_class 2 2 4 ;;
        *) die "协议设置错误: ${protocol_code}" ;;
    esac
}

setup_cluster_nodes() {
    local OPTIND=1
    local opt=""
    local config_num=0
    local data_num=0
    local bm_num=0
    local dcn_str=""
    local check_config_num=0
    local check_data_num=0
    local total_nodes=0
    local flag=0
    local str1=""
    local i=0
    local j=0
    local t_wait=0

    while getopts 'c:d:t:' opt; do
        case "${opt}" in
            c) config_num="${OPTARG}" ;;
            d) data_num="${OPTARG}" ;;
            t) bm_num="${OPTARG}" ;;
            *) die "未知参数: -${OPTARG}" ;;
        esac
    done

    if [ "${config_num}" -le 0 ] || [ "${data_num}" -le 0 ]; then
        die "请输入 ConfigNode 和 DataNode 的启动数量"
    fi

    for ((j = 1; j <= config_num; j++)); do
        if [ -z "${dcn_str}" ]; then
            dcn_str="${DATA_NODE_CONFIG_NODES[${j}]}"
        else
            dcn_str="${dcn_str},${DATA_NODE_CONFIG_NODES[${j}]}"
        fi
    done

    log "开始重置环境"
    for ((i = 1; i < ${#IP_LIST[@]}; i++)); do
        remote_exec "${IP_LIST[${i}]}" "sudo reboot"
    done

    sleep 180

    for ((i = 1; i < ${#IP_LIST[@]}; i++)); do
        log "setting env to ${IP_LIST[${i}]} ..."
        remote_exec "${IP_LIST[${i}]}" "rm -rf ${TEST_PATH}"
        remote_exec "${IP_LIST[${i}]}" "mkdir -p ${TEST_PATH}"
        scp -r "${TEST_PATH}/"* "${ACCOUNT}@${IP_LIST[${i}]}:${TEST_PATH}/"
    done

    for ((j = 1; j <= bm_num; j++)); do
        remote_exec "${BENCHMARK_IP_LIST[${j}]}" "rm -rf ${BM_PATH}/logs"
        remote_exec "${BENCHMARK_IP_LIST[${j}]}" "rm -rf ${BM_PATH}/data"
    done

    log "开始部署 ConfigNode"
    for ((i = 1; i <= config_num; i++)); do
        remote_exec "${CONFIG_NODE_IP_LIST[${i}]}" "echo \"cn_internal_address=${CONFIG_NODE_IP_LIST[${i}]}\" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"
        remote_exec "${CONFIG_NODE_IP_LIST[${i}]}" "echo \"cn_seed_config_node=${CONFIG_NODE_CONFIG_NODES[${i}]}\" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"
        remote_exec "${CONFIG_NODE_IP_LIST[${i}]}" "echo \"schema_replication_factor=${CONFIG_SCHEMA_REPLICATION_FACTOR[${i}]}\" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"
        remote_exec "${CONFIG_NODE_IP_LIST[${i}]}" "echo \"data_replication_factor=${CONFIG_DATA_REPLICATION_FACTOR[${i}]}\" >> ${TEST_CONFIGNODE_PATH}/conf/iotdb-system.properties"
    done

    log "开始部署 DataNode"
    for ((i = 1; i <= data_num; i++)); do
        remote_exec "${DATA_NODE_IP_LIST[${i}]}" "echo \"dn_rpc_address=${DATA_NODE_IP_LIST[${i}]}\" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties"
        remote_exec "${DATA_NODE_IP_LIST[${i}]}" "echo \"dn_internal_address=${DATA_NODE_IP_LIST[${i}]}\" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties"
        remote_exec "${DATA_NODE_IP_LIST[${i}]}" "echo \"dn_seed_config_node=${dcn_str}\" >> ${TEST_DATANODE_PATH}/conf/iotdb-system.properties"
    done

    for ((j = 1; j <= config_num; j++)); do
        log "starting IoTDB ConfigNode on ${CONFIG_NODE_IP_LIST[${j}]} ..."
        remote_exec "${CONFIG_NODE_IP_LIST[${j}]}" "${TEST_CONFIGNODE_PATH}/sbin/start-confignode.sh > /dev/null 2>&1 &"
        sleep 10
    done

    for ((j = 1; j <= data_num; j++)); do
        log "starting IoTDB DataNode on ${DATA_NODE_IP_LIST[${j}]} ..."
        remote_exec "${DATA_NODE_IP_LIST[${j}]}" "${TEST_DATANODE_PATH}/sbin/start-datanode.sh -H ${TEST_DATANODE_PATH}/dn_dump.hprof > /dev/null 2>&1 &"
    done

    sleep 60

    for ((j = 1; j <= config_num; j++)); do
        for ((t_wait = 0; t_wait <= 3; t_wait++)); do
            str1="$(remote_exec "${CONFIG_NODE_IP_LIST[${j}]}" "jps | grep -w ConfigNode | grep -v grep | wc -l" || true)"
            if [ "${str1}" = "1" ]; then
                log "ConfigNode has been started on PC:${CONFIG_NODE_IP_LIST[${j}]}"
                check_config_num=$((check_config_num + 1))
                break
            fi
            log "ConfigNode has not been started on PC:${CONFIG_NODE_IP_LIST[${j}]}"
            sleep 30
        done
    done

    for ((j = 1; j <= data_num; j++)); do
        for ((t_wait = 0; t_wait <= 3; t_wait++)); do
            str1="$(remote_exec "${DATA_NODE_IP_LIST[${j}]}" "jps | grep -w DataNode | grep -v grep | wc -l" || true)"
            if [ "${str1}" = "1" ]; then
                log "DataNode has been started on PC:${DATA_NODE_IP_LIST[${j}]}"
                check_data_num=$((check_data_num + 1))
                break
            fi
            log "DataNode has not been started on PC:${DATA_NODE_IP_LIST[${j}]}"
            sleep 30
        done
    done

    total_nodes=$((config_num + data_num))
    for ((j = 1; j <= data_num; j++)); do
        flag=0
        for ((t_wait = 0; t_wait <= 20; t_wait++)); do
            str1="$(remote_exec "${DATA_NODE_IP_LIST[${j}]}" "${TEST_DATANODE_PATH}/sbin/start-cli.sh -h ${DATA_NODE_IP_LIST[${j}]} -p 6667 -e \"show cluster\" | grep -F \"Total line number = ${total_nodes}\"" || true)"
            if [ "${str1}" = "Total line number = ${total_nodes}" ]; then
                log "All Nodes is ready on ${DATA_NODE_IP_LIST[${j}]}"
                flag=1
                break
            fi
            log "All Nodes is not ready on ${DATA_NODE_IP_LIST[${j}]}. Please wait ..."
            sleep 3
        done

        if [ "${flag}" -eq 0 ]; then
            die "All Nodes is not ready on ${DATA_NODE_IP_LIST[${j}]}"
        fi
    done

    if [ "${check_config_num}" -ne "${config_num}" ] || [ "${check_data_num}" -ne "${data_num}" ]; then
        die "启动节点数不符合预期: ConfigNode=${check_config_num}/${config_num}, DataNode=${check_data_num}/${data_num}"
    fi

    log "All ${check_config_num} ConfigNodes and ${check_data_num} DataNodes have been started"
    sleep 60
}

start_cluster_benchmarks() {
    local bm_num="$1"
    local j=0

    if [ "${bm_num}" -gt 0 ]; then
        for ((j = 1; j <= bm_num; j++)); do
            remote_exec "${BENCHMARK_IP_LIST[${j}]}" "rm -rf ${BM_PATH}"
            scp -r "${BM_PATH}" "${ACCOUNT}@${BENCHMARK_IP_LIST[${j}]}:${BM_PATH}"
            remote_exec "${BENCHMARK_IP_LIST[${j}]}" "rm -rf ${BM_PATH}/conf/config.properties"
            scp -r "${BM_PATH}/conf/config.properties" "${ACCOUNT}@${BENCHMARK_IP_LIST[${j}]}:${BM_PATH}/conf/config.properties"
            remote_exec "${BENCHMARK_IP_LIST[${j}]}" "cd ${BM_PATH}; ${BM_PATH}/benchmark.sh > /dev/null 2>&1 &" &
        done
        wait
        log "All BMs have been started"
    fi
}

create_remote_stuck_result_csv() {
    local host="$1"
    local result_line="INGESTION ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1 ,-1"

    remote_exec "${host}" "mkdir -p ${BM_PATH}/data/csvOutput; : > ${BM_PATH}/data/Stuck_result.csv; i=0; while [ \${i} -lt 100 ]; do echo '${result_line}' >> ${BM_PATH}/data/Stuck_result.csv; i=\$((i + 1)); done"
}

monitor_test_status() {
    local benchmark_finished=0
    local str1=""
    local now_epoch=0
    local elapsed=0
    local j=0

    while true; do
        benchmark_finished=0
        for ((j = 1; j <= CLUSTER_BENCHMARK_COUNT; j++)); do
            str1="$(remote_exec "${BENCHMARK_IP_LIST[${j}]}" "jps | grep -w App | grep -v grep | wc -l" 2>/dev/null || true)"
            if [ "${str1}" = "1" ]; then
                log "benchmark is still running on ${BENCHMARK_IP_LIST[${j}]}"
            else
                log "benchmark finished on ${BENCHMARK_IP_LIST[${j}]}"
                benchmark_finished=$((benchmark_finished + 1))
            fi
        done

        if [ "${benchmark_finished}" -eq "${CLUSTER_BENCHMARK_COUNT}" ]; then
            end_time="$(current_datetime)"
            cost_time=$(( $(datetime_to_epoch "${end_time}") - $(datetime_to_epoch "${start_time}") ))
            return 0
        fi

        now_epoch="$(date +%s)"
        elapsed=$((now_epoch - m_start_time))
        if [ "${elapsed}" -ge "${MONITOR_TIMEOUT_SECONDS}" ]; then
            log "测试超时，生成兜底结果"
            end_time="-1"
            cost_time=-1
            create_remote_stuck_result_csv "${BENCHMARK_IP_LIST[1]}"
            return 1
        fi

        sleep "${MONITOR_POLL_INTERVAL_SECONDS}"
    done
}

collect_monitor_data() {
    local node_index="$1"
    local node_host="${DATA_NODE_IP_LIST[${node_index}]}"

    [ -n "${node_host}" ] || die "无效的数据节点索引: ${node_index}"

    dataFileSize=0
    walFileSize=0
    numOfSe0Level=0
    numOfUnse0Level=0
    maxNumofOpenFiles=0
    maxNumofThread=0
    maxCPULoad=0
    avgCPULoad=0
    maxDiskIOOpsRead=0
    maxDiskIOOpsWrite=0
    maxDiskIOSizeRead=0
    maxDiskIOSizeWrite=0

    collect_resource_monitor_data "${node_host}" "${DISK_ID_PATTERN}" "${m_start_time}" "${m_end_time}"
}

copy_benchmark_case_config() {
    local series_type="$1"
    local workload_type="$2"
    local config_source="${ATMOS_PATH}/conf/${TEST_TYPE}/${series_type}/${workload_type}"

    copy_benchmark_config "${config_source}"
}

prepare_benchmark_result_dir() {
    safe_rm "${BENCHMARK_RESULT_PATH}"
    mkdir -p "${BENCHMARK_RESULT_PATH}"
}

fetch_benchmark_results() {
    local remote_result_pattern="${ACCOUNT}@${BENCHMARK_IP_LIST[1]}:${BM_PATH}/data/csvOutput/*result.csv"

    prepare_benchmark_result_dir
    if ! scp -r "${remote_result_pattern}" "${BENCHMARK_RESULT_PATH}/"; then
        die "复制 benchmark 结果失败: ${remote_result_pattern}"
    fi
}

find_case_result_csv() {
    local had_nullglob=0
    local files=()

    if shopt -q nullglob; then
        had_nullglob=1
    else
        shopt -s nullglob
    fi

    files=("${BENCHMARK_RESULT_PATH}/"*result.csv)

    if [ "${had_nullglob}" -eq 0 ]; then
        shopt -u nullglob
    fi

    if [ "${#files[@]}" -gt 0 ]; then
        printf '%s\n' "${files[0]}"
    fi
}

parse_benchmark_result() {
    local csv_file="$1"

    [ -f "${csv_file}" ] || die "缺少 benchmark 结果文件: ${csv_file}"

    read -r okOperation okPoint failOperation failPoint throughput < <(
        awk -F, '/^INGESTION/ {print $2, $3, $4, $5, $6; exit}' "${csv_file}"
    )
    read -r Latency MIN P10 P25 MEDIAN P75 P90 P95 P99 P999 MAX < <(
        awk -F, '/^INGESTION/ {count++; if (count == 2) {print $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12; exit}}' "${csv_file}"
    )
}

build_case_backup_dir() {
    build_scoped_path "${BUCKUP_PATH}" "$1" "${commit_date_time}_${commit_id}_$2_$3"
}

insert_result_row() {
    local node_id="$1"
    local remark="$2"
    local protocol_code="$3"
    local insert_sql=""

    insert_sql="insert into ${TABLENAME} (commit_date_time,test_date_time,commit_id,author,node_id,ts_type,okPoint,okOperation,failPoint,failOperation,throughput,Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,walFileSize,avgCPULoad,maxCPULoad,maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,remark,protocol) values(${commit_date_time},${test_date_time},$(sql_quote "${commit_id}"),$(sql_quote "${author}"),${node_id},$(sql_quote "${ts_type}"),${okPoint},${okOperation},${failPoint},${failOperation},${throughput},${Latency},${MIN},${P10},${P25},${MEDIAN},${P75},${P90},${P95},${P99},${P999},${MAX},${numOfSe0Level},$(sql_quote "${start_time}"),$(sql_quote "${end_time}"),${cost_time},${numOfUnse0Level},${dataFileSize},${maxNumofOpenFiles},${maxNumofThread},${walFileSize},${avgCPULoad},${maxCPULoad},${maxDiskIOSizeRead},${maxDiskIOSizeWrite},${maxDiskIOOpsRead},${maxDiskIOOpsWrite},$(sql_quote "${remark}"),$(sql_quote "${protocol_code}"))"
    mysql_exec "${insert_sql}"
}

backup_case_logs() {
    local backup_dir="$1"
    local node_id="$2"
    local node_backup_dir="${backup_dir}/${node_id}"

    sudo mkdir -p "${node_backup_dir}/DN"

    if ((node_id <= CLUSTER_CONFIG_COUNT)); then
        sudo mkdir -p "${node_backup_dir}/CN"
        if ! scp -r "${ACCOUNT}@${CONFIG_NODE_IP_LIST[${node_id}]}:${TEST_CONFIGNODE_PATH}/logs" "${node_backup_dir}/CN"; then
            log "复制 ConfigNode 日志失败: node=${node_id}"
        fi
    fi
    if ! scp -r "${ACCOUNT}@${DATA_NODE_IP_LIST[${node_id}]}:${TEST_DATANODE_PATH}/logs" "${node_backup_dir}/DN"; then
        log "复制 DataNode 日志失败: node=${node_id}"
    fi
}

stop_cluster() {
    local i=0

    for ((i = 1; i < ${#IP_LIST[@]}; i++)); do
        remote_exec "${IP_LIST[${i}]}" "${TEST_DATANODE_PATH}/sbin/stop-standalone.sh > /dev/null 2>&1 &" || true
    done
}

test_operation() {
    local series_type="$1"
    local workload_type="$2"
    local protocol_code="$3"
    local csv_output_file=""
    local backup_dir=""
    local node_id=0

    ts_type="${series_type}"
    data_type="${workload_type}"

    log "开始测试 ${series_type}/${workload_type}, protocol=${protocol_code}"

    set_env
    modify_iotdb_config
    apply_protocol_settings "${protocol_code}"
    copy_benchmark_case_config "${series_type}" "${workload_type}"
    sed -i "s/^HOST=.*$/HOST=${DATA_NODE_IP_LIST[1]}/g" "${BM_PATH}/conf/config.properties"

    setup_cluster_nodes -c "${CLUSTER_CONFIG_COUNT}" -d "${CLUSTER_DATA_COUNT}" -t "${CLUSTER_BENCHMARK_COUNT}"
    if ! "${TEST_DATANODE_PATH}/sbin/start-cli.sh" -h "${DATA_NODE_IP_LIST[1]}" -p 6667 -e "ALTER USER root SET PASSWORD '${IOTDB_PW}'" >/dev/null 2>&1; then
        die "Failed to set root password before starting benchmark"
    fi
    start_cluster_benchmarks "${CLUSTER_BENCHMARK_COUNT}"

    start_time="$(current_datetime)"
    m_start_time="$(date +%s)"
    log "测试开始: ${series_type}/${workload_type}, protocol=${protocol_code}"

    sleep 60
    monitor_test_status || true
    m_end_time="$(date +%s)"

    fetch_benchmark_results
    csv_output_file="$(find_case_result_csv)"
    [ -n "${csv_output_file}" ] || die "未找到 benchmark 结果文件"
    parse_benchmark_result "${csv_output_file}"

    backup_dir="$(build_case_backup_dir "${series_type}" "${workload_type}" "${protocol_code}")"
    prepare_backup_directory "${backup_dir}"

    for ((node_id = 1; node_id <= CLUSTER_DATA_COUNT; node_id++)); do
        collect_monitor_data "${node_id}"
        insert_result_row "${node_id}" "${workload_type}" "${protocol_code}"
        backup_case_logs "${backup_dir}" "${node_id}"
    done

    stop_cluster
    sleep 10

    sudo cp -rf "${BENCHMARK_RESULT_PATH}/." "${backup_dir}/"
    if ! scp -r "${ACCOUNT}@${BENCHMARK_IP_LIST[1]}:${BM_PATH}/logs" "${backup_dir}/"; then
        log "复制 benchmark 日志失败"
    fi
}

run_case() {
    local series_type="$1"
    local workload_type="$2"
    local protocol_code="$3"

    if ! test_operation "${series_type}" "${workload_type}" "${protocol_code}"; then
        log "用例执行失败: ${series_type}/${workload_type}, protocol=${protocol_code}"
    fi
}

run_default_cases() {
    run_case common seq_w 223
    run_case aligned seq_w 223
    run_case aligned seq_w 222
    run_case aligned seq_w 224
    run_case tablemode seq_w 223
    run_case common unseq_w 223
    run_case aligned unseq_w 223
    run_case aligned unseq_w 222
    run_case aligned unseq_w 224
    run_case aligned seq_rw 223
    run_case aligned unseq_rw 223
    run_case tablemode unseq_w 223
    run_case tablemode seq_rw 223
    run_case tablemode unseq_rw 223
}

main() {
    trap restore_test_type_file EXIT

    ensure_runtime_dependencies
    check_password
    check_benchmark_version
    mark_test_in_progress

    if ! fetch_next_commit; then
        log "未发现待执行的 commit，60 秒后退出"
        sleep 60
        return 0
    fi

    update_task_status "ontesting"
    log "当前版本 ${commit_id} 未执行过测试，即将编译后启动"

    init_items
    test_date_time="$(date +%Y%m%d%H%M%S)"

    run_default_cases

    log "本轮测试 ${test_date_time} 已结束"
    update_task_status "done"
    mark_older_commits_skip
}

main "$@"
