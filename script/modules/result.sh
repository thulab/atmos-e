#!/usr/bin/env bash

# 根据结果类型分发写入操作，并转换 SQL 字段值。

# 查找并调用与结果类型对应的结果写入函数。
result_writer() {
    local writer="$1"
    shift
    local function_name="result_write_${writer}"

    declare -F "${function_name}" >/dev/null 2>&1 || return 20
    "${function_name}" "$@"
}

# 按字段类型将值转换为可嵌入 SQL 的文本。
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
