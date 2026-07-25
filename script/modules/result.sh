#!/usr/bin/env bash

result_writer() {
    local writer="$1"
    shift
    local function_name="result_write_${writer}"

    declare -F "${function_name}" >/dev/null 2>&1 || return 20
    "${function_name}" "$@"
}

result_sql_value() {
    local value="${1:-}"
    local kind="${2:-text}"
    case "${kind}" in
        number) printf '%s' "${value:-0}" ;;
        nullable) sql_maybe_quote "${value}" ;;
        text) sql_quote "${value}" ;;
        *) return 20 ;;
    esac
}
