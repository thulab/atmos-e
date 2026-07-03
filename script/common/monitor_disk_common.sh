#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "monitor_disk_common.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "monitor_disk_common.sh requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi

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
    local fallback_disk_id="${DEFAULT_DISK_ID:-vdc}"

    for current_disk_id in "$@"; do
        if [ -z "${regex}" ]; then
            regex="${current_disk_id}"
        else
            regex="${regex}|${current_disk_id}"
        fi
    done

    [ -n "${regex}" ] || regex="${fallback_disk_id}"
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
    local fallback_disk_id="${DEFAULT_DISK_ID:-vdc}"
    local -a detected_disk_ids=()
    local -a monitor_target_paths=()

    disk_id_regex="^${fallback_disk_id}$"

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
        log "resolved monitor disk ids from ${monitor_target_paths[*]:-${TEST_IOTDB_PATH}}: ${detected_disk_ids[*]}"
    else
        log "failed to resolve monitor disk id from ${monitor_target_paths[*]:-${TEST_IOTDB_PATH}}, fallback to ${fallback_disk_id}"
    fi
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
