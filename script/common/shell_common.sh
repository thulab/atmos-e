#!/usr/bin/env bash

# 提供通用日志、参数校验、时间格式、数据库及安全文件操作函数。

if [ -z "${BASH_VERSION:-}" ]; then
    echo "shell_common.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "shell_common.sh requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi

# 输出带当前时间戳的日志消息。
log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

# 输出错误日志并以失败状态终止当前脚本。
die() {
    log "ERROR: $*"
    exit 1
}

# 检查指定命令是否已安装且可执行。
require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# 依次检查传入的全部命令是否可用。
require_commands() {
    local cmd=""

    for cmd in "$@"; do
        require_command "${cmd}"
    done
}

# 移除字符串首尾的空白字符并输出结果。
trim() {
    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

# 输出当前本地时间，格式为年月日时分秒。
current_datetime() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 输出当前 Unix 毫秒时间戳。
current_epoch_ms() {
    date +%s%3N
}

# 将日期时间字符串转换为 Unix 秒级时间戳。
datetime_to_epoch() {
    date -d "$1" +%s
}

# 删除日期时间字符串中的非数字字符。
normalize_datetime() {
    printf '%s' "$1" | tr -cd '0-9'
}

# 转义 SQL 字符串中的反斜杠和单引号并加引号。
sql_quote() {
    local value="${1:-}"

    value="${value//\\/\\\\}"
    value="$(printf '%s' "${value}" | sed "s/'/''/g")"
    printf "'%s'" "${value}"
}

# 对非空值执行 SQL 字符串转义，空值输出 NULL。
sql_maybe_quote() {
    local value="${1:-}"

    if [ -n "${value}" ]; then
        sql_quote "${value}"
    else
        printf 'NULL'
    fi
}

# 使用当前数据库连接配置执行 MySQL 查询。
mysql_exec() {
    local sql="$1"
    local mysql_port="${MYSQL_PORT:-${PORT:-}}"
    local mysql_username="${MYSQL_USERNAME:-${USERNAME:-}}"
    local mysql_password="${MYSQL_PASSWORD:-${PASSWORD:-}}"

    MYSQL_PWD="${mysql_password}" mysql -N -B \
        -h"${MYSQLHOSTNAME}" -P"${mysql_port}" -u"${mysql_username}" \
        "${DBNAME}" -e "${sql}"
}

# 检查数据库密码是否已配置。
check_password() {
    local mysql_password="${MYSQL_PASSWORD:-${PASSWORD:-}}"

    [ -n "${mysql_password}" ] || die "ATMOS_DB_PASSWORD is not set"
}

# 判断路径是否位于允许执行删除操作的目录范围内。
path_is_safe() {
    local path="$1"

    [ -n "${path}" ] || return 1
    case "${path}" in
        "/"|"/data"|"/nasdata"|".") return 1 ;;
        "${INIT_PATH}"/*|"${TEST_INIT_PATH}"/*|"${BACKUP_PATH}"/*) return 0 ;;
        *) return 1 ;;
    esac
}

# 仅对安全目录范围内的路径执行递归删除。
sudo_safe_rm() {
    local path="$1"
    [ -e "${path}" ] || return 0
    path_is_safe "${path}" || die "refuse to remove unsafe path: ${path}"
    sudo rm -rf -- "${path}"
}

# 源路径存在时复制到目标位置，不存在时记录并跳过。
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

# 查找指定 Java 进程并终止匹配到的进程。
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

# 依次清理 IoTDB DataNode、ConfigNode 和主进程。
check_iotdb_pid() {
    check_pid_and_kill "DataNode" "DataNode"
    check_pid_and_kill "ConfigNode" "ConfigNode"
    check_pid_and_kill "IoTDB" "IoTDB"
}

# 将字节数转换为 GiB 并保留两位小数。
bytes_to_gib() {
    awk -v value="${1:-0}" 'BEGIN { printf "%.2f\n", value / 1073741824 }'
}

# 将输入值转换为整数并输出。
to_int() {
    awk -v value="${1:-0}" 'BEGIN { printf "%d\n", value }'
}

# 将非空测试类型写入调度器状态文件。
write_test_type_file() {
    local value="$1"

    [ -n "${value}" ] || {
        log "cannot write empty test type"
        return 1
    }
    mkdir -p "${INIT_PATH}"
    printf '%s\n' "${value}" > "${INIT_PATH}/test_type_file"
}

# 将调度器状态设置为测试执行中。
mark_test_in_progress() {
    write_test_type_file "ontesting"
}

# 将调度器状态恢复为当前测试类型。
restore_test_type_file() {
    local current_test_type="${1:-${TEST_TYPE:-${test_type:-}}}"

    write_test_type_file "${current_test_type}"
}
