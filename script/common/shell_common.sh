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
    mkdir -p "${INIT_PATH}"
    printf '%s\n' "${TEST_TYPE}" > "${INIT_PATH}/test_type_file"
}
