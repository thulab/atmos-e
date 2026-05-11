#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "insert_common.sh 需要使用 bash 运行" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "insert_common.sh 需要使用非 posix 模式的 bash 运行" >&2
    return 1 2>/dev/null || exit 1
fi

: "${TEST_IP:?在 source insert_common.sh 之前必须设置 TEST_IP}"
: "${TEST_TYPE:?在 source insert_common.sh 之前必须设置 TEST_TYPE}"

if ! declare -p PROTOCOL_LIST >/dev/null 2>&1; then
    readonly -a PROTOCOL_LIST=(223)
fi
if ! declare -p TS_LIST >/dev/null 2>&1; then
    readonly -a TS_LIST=(common aligned tempaligned tablemode)
fi
if ! declare -p API_LIST >/dev/null 2>&1; then
    readonly -a API_LIST=(SESSION_BY_TABLET)
fi
if ! declare -p METRIC_SERVER >/dev/null 2>&1; then
    readonly METRIC_SERVER="111.200.37.158:19090"
else
    readonly METRIC_SERVER
fi
if ! declare -p BENCHMARK_WARMUP_SECONDS >/dev/null 2>&1; then
    readonly BENCHMARK_WARMUP_SECONDS=60
else
    readonly BENCHMARK_WARMUP_SECONDS
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/runtime_common.sh
source "${SCRIPT_DIR}/runtime_common.sh"

readonly TABLENAME="test_result_${TEST_TYPE}"
readonly TABLENAME_T="test_result_${TEST_TYPE}"
readonly IOTDB_PW="TimechoDB@2021"
readonly DEFAULT_DISK_ID="vdc"

result_table="${TABLENAME}"
disk_id_regex="^${DEFAULT_DISK_ID}$"
maxCPULoad=0
avgCPULoad=0
maxDiskIOOpsRead=0
maxDiskIOOpsWrite=0
maxDiskIOSizeRead=0
maxDiskIOSizeWrite=0

ensure_runtime_dependencies() {
    ensure_base_runtime_dependencies
    require_command bc
}

append_iotdb_properties() {
    local properties_file="$1"

    cat >> "${properties_file}" <<EOF
enable_seq_space_compaction=false
enable_unseq_space_compaction=false
enable_cross_space_compaction=false
EOF
}

normalize_decimal() {
    awk -v value="${1:-0}" 'BEGIN {
        value += 0
        text = sprintf("%.10f", value)
        sub(/0+$/, "", text)
        sub(/\.$/, "", text)
        if (text == "" || text == "-0") {
            text = "0"
        }
        print text
    }'
}

get_monitor_disk_fallback_path() {
    local data_path="${TEST_IOTDB_PATH}/data"

    if [ -d "${data_path}" ]; then
        printf '%s\n' "${data_path}"
        return 0
    fi

    printf '%s\n' "${TEST_IOTDB_PATH}"
}

get_iotdb_property_value() {
    local properties_file="$1"
    local property_key="$2"

    awk -v property_key="${property_key}" '
        /^[[:space:]]*#/ { next }
        {
            line = $0
            sub(/\r$/, "", line)
            if (line ~ "^[[:space:]]*" property_key "[[:space:]]*=") {
                sub("^[[:space:]]*" property_key "[[:space:]]*=[[:space:]]*", "", line)
                last_value = line
            }
        }
        END {
            if (last_value != "") {
                print last_value
            }
        }
    ' "${properties_file}"
}

split_iotdb_path_list() {
    local value="$1"
    local item=""
    local -a items=()

    value="${value//;/,}"
    value="${value//\"/}"
    IFS=',' read -r -a items <<< "${value}"
    for item in "${items[@]}"; do
        item="$(trim "${item}")"
        [ -n "${item}" ] || continue
        printf '%s\n' "${item}"
    done
}

normalize_monitor_target_path() {
    local path="$1"

    path="$(trim "${path}")"
    path="${path%/}"

    case "${path}" in
        /*)
            printf '%s\n' "${path}"
            ;;
        *)
            printf '%s\n' "${TEST_IOTDB_PATH}/${path}"
            ;;
    esac
}

get_monitor_disk_target_paths() {
    local properties_file="${TEST_IOTDB_PATH}/conf/iotdb-system.properties"
    local property_key=""
    local property_value=""
    local raw_path=""
    local normalized_path=""
    local found_configured_path=0
    local -a property_keys=(dn_data_dirs dn_wal_dirs)

    if [ -f "${properties_file}" ]; then
        for property_key in "${property_keys[@]}"; do
            property_value="$(get_iotdb_property_value "${properties_file}" "${property_key}")"
            [ -n "${property_value}" ] || continue

            while IFS= read -r raw_path; do
                [ -n "${raw_path}" ] || continue
                normalized_path="$(normalize_monitor_target_path "${raw_path}")"
                [ -n "${normalized_path}" ] || continue
                printf '%s\n' "${normalized_path}"
                found_configured_path=1
            done < <(split_iotdb_path_list "${property_value}")
        done
    fi

    if [ "${found_configured_path}" -eq 0 ]; then
        get_monitor_disk_fallback_path
    fi
}

find_existing_monitor_path() {
    local path="$1"

    while [ ! -e "${path}" ] && [ "${path}" != "/" ]; do
        path="${path%/*}"
        [ -n "${path}" ] || path="/"
    done

    [ -e "${path}" ] || return 1
    printf '%s\n' "${path}"
}

contains_value() {
    local expected="$1"
    shift

    local actual=""
    for actual in "$@"; do
        [ "${actual}" = "${expected}" ] && return 0
    done

    return 1
}

build_disk_id_regex() {
    local regex=""
    local current_disk_id=""

    for current_disk_id in "$@"; do
        if [ -z "${regex}" ]; then
            regex="${current_disk_id}"
        else
            regex="${regex}|${current_disk_id}"
        fi
    done

    [ -n "${regex}" ] || regex="${DEFAULT_DISK_ID}"
    printf '^(%s)$\n' "${regex}"
}

detect_disk_id_from_path() {
    local target_path="$1"
    local existing_path=""
    local source_device=""
    local resolved_device=""
    local parent_device=""

    command -v findmnt >/dev/null 2>&1 || return 1
    command -v lsblk >/dev/null 2>&1 || return 1

    existing_path="$(find_existing_monitor_path "${target_path}" || true)"
    [ -n "${existing_path}" ] || return 1

    source_device="$(findmnt -no SOURCE --target "${existing_path}" 2>/dev/null | awk 'NF { print; exit }')"
    [ -n "${source_device}" ] || return 1

    source_device="${source_device%%[*}"
    if command -v readlink >/dev/null 2>&1; then
        resolved_device="$(readlink -f "${source_device}" 2>/dev/null || printf '%s\n' "${source_device}")"
    else
        resolved_device="${source_device}"
    fi

    [ -b "${resolved_device}" ] || return 1

    while true; do
        parent_device="$(lsblk -ndo PKNAME "${resolved_device}" 2>/dev/null | awk 'NF { print; exit }')"
        [ -n "${parent_device}" ] || break
        resolved_device="/dev/${parent_device}"
    done

    printf '%s\n' "${resolved_device##*/}"
}

resolve_monitor_disk_id() {
    local target_path=""
    local detected_disk_id=""
    local -a detected_disk_ids=()
    local -a monitor_target_paths=()

    disk_id_regex="^${DEFAULT_DISK_ID}$"

    while IFS= read -r target_path; do
        [ -n "${target_path}" ] || continue
        monitor_target_paths+=("${target_path}")
        detected_disk_id="$(detect_disk_id_from_path "${target_path}" || true)"
        [ -n "${detected_disk_id}" ] || continue

        if ! contains_value "${detected_disk_id}" "${detected_disk_ids[@]:-}"; then
            detected_disk_ids+=("${detected_disk_id}")
        fi
    done < <(get_monitor_disk_target_paths)

    if [ "${#detected_disk_ids[@]:-}" -gt 0 ]; then
        disk_id_regex="$(build_disk_id_regex "${detected_disk_ids[@]:-}")"
        log "已从 ${monitor_target_paths[*]:-${TEST_IOTDB_PATH}} 解析出磁盘 ID: ${detected_disk_ids[*]}"
    else
        log "无法从 ${monitor_target_paths[*]:-${TEST_IOTDB_PATH}} 解析磁盘 ID，回退到 ${DEFAULT_DISK_ID}"
    fi
}

sendMsg() {
    local error_type="$1"
    local date_time=""
    local test_label="${TEST_TYPE:-性能测试}"
    local headline=""
    local msgbody=""
    local dingtalk_token="f2d691d45da9a0307af8bbd853e90d0785dbaa3a3b0219dd2816882e19859e62"
    local dingtalk_url="https://oapi.dingtalk.com/robot/send?access_token=${dingtalk_token}"
    local json_data=""

    date_time="$(date '+%Y-%m-%d %H:%M:%S')"

    case "${error_type}" in
        1)
            headline="吞吐量监控异常告警"
            msgbody="[Atmos性能测试告警]\n错误类型：吞吐量异常\n告警时间：${date_time}\n测试类型：${test_label}\n当前吞吐量：${2}\n控制上限：${3}\n控制下限：${4}\n历史均值：${5}\n"
            ;;
        2)
            headline="${test_label}代码编译失败"
            msgbody="错误类型：${test_label}代码编译失败\n报错时间：${date_time}\n报错 Commit：${commit_id:-N/A}\n提交人：${author:-N/A}\n报错信息：${3:-N/A}"
            ;;
        *)
            log "未知错误类型: ${error_type}"
            return 1
            ;;
    esac

    json_data=$(cat <<EOF
{
    "msgtype": "text",
    "text": {
        "content": "${msgbody}"
    }
}
EOF
)

    curl -s -X POST \
        -H 'Content-Type: application/json' \
        -d "${json_data}" \
        "${dingtalk_url}" >/dev/null 2>&1 &

    log "已发送钉钉告警通知: ${headline}"
}

check_throughput_monitor() {
    local current_commit_date_time="$1"
    local current_throughput="$2"
    local protocol_code="$3"
    local current_ts_type="$4"
    local current_api_type="$5"
    local data=""
    local data_count=0
    local mean=""
    local std=""
    local ucl=""
    local lcl=""

    data="$(mysql_exec "
        SELECT throughput
        FROM ${result_table}
        WHERE commit_date_time < '${current_commit_date_time}'
        AND ts_type = '${current_ts_type}'
        AND api_type = '${current_api_type}'
        AND protocol = '${protocol_code}'
        AND throughput > 0
        ORDER BY commit_date_time DESC
        LIMIT 100
    ")" || {
        log "监控：获取历史数据失败"
        return 0
    }

    data_count="$(printf '%s\n' "${data}" | awk 'NF { count++ } END { print count + 0 }')"
    if [ "${data_count}" -lt 20 ]; then
        log "监控：历史数据不足（${data_count} 条），跳过检查"
        return 0
    fi

    mean="$(printf '%s\n' "${data}" | awk '
        { sum += $1; sumsq += $1 * $1 }
        END {
            if (NR > 0) {
                printf "%.10f\n", sum / NR
            } else {
                print 0
            }
        }
    ')"
    std="$(printf '%s\n' "${data}" | awk '
        { sum += $1; sumsq += $1 * $1 }
        END {
            if (NR > 0) {
                var = sumsq / NR - (sum / NR) ^ 2
                if (var < 0) {
                    var = 0
                }
                printf "%.10f\n", sqrt(var)
            } else {
                print 0
            }
        }
    ')"

    mean="$(normalize_decimal "${mean}")"
    std="$(normalize_decimal "${std}")"
    ucl="$(awk -v mean="${mean}" -v std="${std}" 'BEGIN { printf "%.10f\n", mean + 3 * std }')"
    lcl="$(awk -v mean="${mean}" -v std="${std}" 'BEGIN { value = mean - 3 * std; if (value < 0) value = 0; printf "%.10f\n", value }')"
    ucl="$(normalize_decimal "${ucl}")"
    lcl="$(normalize_decimal "${lcl}")"

    log "吞吐量 ${current_throughput} 控制限 [${lcl}, ${ucl}]（均值 ${mean}，标准差 ${std}）"
    if awk -v throughput="${current_throughput}" 'BEGIN { exit !((throughput + 0) > 0) }'; then
        if awk -v throughput="${current_throughput}" -v ucl="${ucl}" 'BEGIN { exit !((throughput + 0) > (ucl + 0)) }' || \
           awk -v throughput="${current_throughput}" -v lcl="${lcl}" 'BEGIN { exit !((throughput + 0) < (lcl + 0) && (lcl + 0) > 0) }'; then
            log "监控报警：吞吐量 ${current_throughput} 超出控制限 [${lcl}, ${ucl}]（均值 ${mean}，标准差 ${std}）"
            sendMsg 1 "${current_throughput}" "${ucl}" "${lcl}" "${mean}"
            return 1
        fi

        log "监控正常：吞吐量 ${current_throughput} 在控制限内 [${lcl}, ${ucl}]"
        return 0
    fi

    log "监控：当前吞吐量不是正数（${current_throughput}），跳过检查"
    return 0
}

init_items() {
    init_common_items
    maxCPULoad=0
    avgCPULoad=0
    maxDiskIOOpsRead=0
    maxDiskIOOpsWrite=0
    maxDiskIOSizeRead=0
    maxDiskIOSizeWrite=0
}

change_root_password() {
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" -e "ALTER USER root SET PASSWORD '${IOTDB_PW}'" >/dev/null 2>&1
}

collect_monitor_data() {
    local ip="${1:-${TEST_IP}}"

    resolve_monitor_disk_id
    collect_resource_monitor_data "${ip}" "${disk_id_regex}" "${m_start_time}" "${m_end_time}"
}

backup_test_data() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local current_api_type="$3"
    local backup_parent="${BACKUP_PATH}/${current_ts_type}_${current_api_type}"
    local backup_dir="${backup_parent}/${commit_date_time}_${commit_id}_${protocol_code}"

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

mv_config_file() {
    local current_ts_type="$1"
    local current_api_type="$2"

    copy_benchmark_config "${ATMOS_PATH}/conf/${TEST_TYPE}/${current_ts_type}_${current_api_type}"
}

parse_benchmark_result() {
    local csv_file="$1"
    local throughput_line=""
    local latency_line=""

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

    IFS=$'\t' read -r okOperation okPoint failOperation failPoint throughput <<< "${throughput_line}"
    IFS=$'\t' read -r Latency MIN P10 P25 MEDIAN P75 P90 P95 P99 P999 MAX <<< "${latency_line}"
}

insert_result_row() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local current_api_type="$3"
    local insert_sql=""

    insert_sql=$(cat <<EOF
insert into ${result_table} (
    commit_date_time,test_date_time,commit_id,author,ts_type,okPoint,okOperation,failPoint,failOperation,throughput,
    Latency,MIN,P10,P25,MEDIAN,P75,P90,P95,P99,P999,MAX,numOfSe0Level,start_time,end_time,cost_time,
    numOfUnse0Level,dataFileSize,maxNumofOpenFiles,maxNumofThread,errorLogSize,walFileSize,avgCPULoad,maxCPULoad,
    maxDiskIOSizeRead,maxDiskIOSizeWrite,maxDiskIOOpsRead,maxDiskIOOpsWrite,api_type,protocol
) values (
    ${commit_date_time},
    ${test_date_time},
    $(sql_quote "${commit_id}"),
    $(sql_quote "${author}"),
    $(sql_quote "${current_ts_type}"),
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
    ${avgCPULoad},
    ${maxCPULoad},
    ${maxDiskIOSizeRead},
    ${maxDiskIOSizeWrite},
    ${maxDiskIOOpsRead},
    ${maxDiskIOOpsWrite},
    $(sql_quote "${current_api_type}"),
    $(sql_quote "${protocol_code}")
)
EOF
)

    mysql_exec "${insert_sql}"
}

test_operation() {
    local protocol_code="$1"
    local current_ts_type="$2"
    local current_api_type="$3"
    local csv_file=""
    local monitor_failed=0

    log "开始测试协议 ${protocol_code} 下的 ${current_ts_type} 时间序列"
    init_items
    cleanup_processes
    set_env
    modify_iotdb_config

    if ! set_protocol_class "${protocol_code}"; then
        log "协议配置无效: ${protocol_code}"
        return 1
    fi

    start_iotdb
    sleep "${STARTUP_GRACE_SECONDS}"
    if ! wait_for_iotdb_ready; then
        end_time="$(current_datetime)"
        log "IoTDB 未能正常启动，记录启动失败结果"
        cost_time=-3
        throughput=-3
        insert_result_row "${protocol_code}" "${current_ts_type}" "${current_api_type}"
        cleanup_processes
        return 1
    fi

    if ! change_root_password; then
        end_time="$(current_datetime)"
        log "root 密码修改失败，记录认证失败结果"
        cost_time=-4
        throughput=-4
        insert_result_row "${protocol_code}" "${current_ts_type}" "${current_api_type}"
        cleanup_processes
        return 1
    fi

    mv_config_file "${current_ts_type}" "${current_api_type}"
    start_benchmark
    start_time="$(current_datetime)"
    m_start_time="$(date +%s)"
    sleep "${BENCHMARK_WARMUP_SECONDS}"

    if ! monitor_test_status "${current_ts_type}" "INGESTION"; then
        monitor_failed=1
    fi

    m_end_time="$(date +%s)"
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" -u root -pw "${IOTDB_PW}" -h 127.0.0.1 -p 6667 -e "flush" >/dev/null 2>&1 || true
    collect_monitor_data "${TEST_IP}"

    csv_file="$(find_result_csv || true)"
    if [ -z "${csv_file}" ] || ! parse_benchmark_result "${csv_file}"; then
        log "benchmark 结果解析失败，记录兜底失败结果"
        [ -n "${end_time}" ] || end_time="$(current_datetime)"
        cost_time=-2
        throughput=-2
        insert_result_row "${protocol_code}" "${current_ts_type}" "${current_api_type}"
        stop_iotdb
        sleep "${BENCHMARK_STOP_WAIT_SECONDS}"
        cleanup_processes
        [ -d "${TEST_IOTDB_PATH}" ] && backup_test_data "${protocol_code}" "${current_ts_type}" "${current_api_type}"
        return 1
    fi

    [ -n "${end_time}" ] || end_time="$(current_datetime)"
    cost_time=$(( $(datetime_to_epoch "${end_time}") - $(datetime_to_epoch "${start_time}") ))
    insert_result_row "${protocol_code}" "${current_ts_type}" "${current_api_type}"

    if (( $(echo "${throughput} > 0" | bc -l 2>/dev/null) )); then
        if ! check_throughput_monitor "${commit_date_time}" "${throughput}" "${protocol_code}" "${current_ts_type}" "${current_api_type}"; then
            log "当前测试结果触发监控告警，但测试流程继续"
        else
            log "当前测试结果吞吐符合历史波动范围"
        fi
    fi

    stop_iotdb
    sleep "${BENCHMARK_STOP_WAIT_SECONDS}"
    cleanup_processes
    [ -d "${TEST_IOTDB_PATH}" ] && backup_test_data "${protocol_code}" "${current_ts_type}" "${current_api_type}"

    return "${monitor_failed}"
}

main() {
    local protocol=""
    local ts=""
    local api=""
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
    log "当前版本 ${commit_id} 尚未执行过测试，开始插入测试流程"

    if [ "${author}" = "Timecho" ]; then
        result_table="${TABLENAME_T}"
    else
        result_table="${TABLENAME}"
    fi

    test_date_time="$(date +%Y%m%d%H%M%S)"
    for protocol in "${PROTOCOL_LIST[@]}"; do
        for ts in "${TS_LIST[@]}"; do
            for api in "${API_LIST[@]}"; do
                if ! test_operation "${protocol}" "${ts}" "${api}"; then
                    task_failed=1
                fi
            done
        done
    done

    log "本轮测试 ${test_date_time} 已结束"
    if [ "${task_failed}" -eq 0 ]; then
        update_task_status "done"
        if [ "${author}" != "Timecho" ]; then
            mark_older_commits_skip
        fi
    else
        update_task_status "RError"
    fi
}
