#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "shell_common.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "shell_common.sh requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
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

current_epoch_ms() {
    date +%s%3N
}

datetime_to_epoch() {
    date -d "$1" +%s
}

normalize_datetime() {
    printf '%s' "$1" | tr -cd '0-9'
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

mysql_exec() {
    local sql="$1"
    local mysql_port="${MYSQL_PORT:-${PORT:-}}"
    local mysql_username="${MYSQL_USERNAME:-${USERNAME:-}}"
    local mysql_password="${MYSQL_PASSWORD:-${PASSWORD:-}}"

    MYSQL_PWD="${mysql_password}" mysql -N -B \
        -h"${MYSQLHOSTNAME}" -P"${mysql_port}" -u"${mysql_username}" \
        "${DBNAME}" -e "${sql}"
}

check_password() {
    local mysql_password="${MYSQL_PASSWORD:-${PASSWORD:-}}"

    [ -n "${mysql_password}" ] || die "ATMOS_DB_PASSWORD is not set"
}

path_is_safe() {
    local path="$1"

    [ -n "${path}" ] || return 1
    case "${path}" in
        "/"|"/data"|"/nasdata"|".") return 1 ;;
        "${INIT_PATH}"/*|"${TEST_INIT_PATH}"/*|"${BACKUP_PATH}"/*) return 0 ;;
        *) return 1 ;;
    esac
}

safe_rm() {
    local path="$1"
    [ -e "${path}" ] || return 0
    path_is_safe "${path}" || die "refuse to remove unsafe path: ${path}"
    rm -rf -- "${path}"
}

sudo_safe_rm() {
    local path="$1"
    [ -e "${path}" ] || return 0
    path_is_safe "${path}" || die "refuse to remove unsafe path: ${path}"
    sudo rm -rf -- "${path}"
}

copy_if_exists() {
    local source="$1"
    local target="$2"
    local label="${3:-$1}"

    if [ ! -e "${source}" ]; then
        log "skip missing ${label}: ${source}"
        return 0
    fi
    cp -rf -- "${source}" "${target}"
}

check_pid_and_kill() {
    local pname="$1"
    local desc="$2"
    local pids=""
    local pid=""

    pids="$(jps | awk -v pname="${pname}" '$2 == pname {print $1}')"
    if [ -z "${pids}" ]; then
        log "no ${desc} process found"
        return 0
    fi
    while IFS= read -r pid; do
        [ -n "${pid}" ] || continue
        kill -9 "${pid}" 2>/dev/null || true
    done <<< "${pids}"
    log "${desc} process stopped"
}

check_iotdb_pid() {
    check_pid_and_kill "DataNode" "DataNode"
    check_pid_and_kill "ConfigNode" "ConfigNode"
    check_pid_and_kill "IoTDB" "IoTDB"
}

bytes_to_gib() {
    awk -v value="${1:-0}" 'BEGIN { printf "%.2f\n", value / 1073741824 }'
}

to_int() {
    awk -v value="${1:-0}" 'BEGIN { printf "%d\n", value }'
}

mark_test_in_progress() {
    mkdir -p "${INIT_PATH}"
    printf 'ontesting\n' > "${INIT_PATH}/test_type_file"
}

restore_test_type_file() {
    local current_test_type="${1:-${TEST_TYPE:-${test_type:-}}}"

    [ -n "${current_test_type}" ] || {
        log "cannot restore test type: TEST_TYPE/test_type is empty"
        return 1
    }
    mkdir -p "${INIT_PATH}"
    printf '%s\n' "${current_test_type}" > "${INIT_PATH}/test_type_file"
}
