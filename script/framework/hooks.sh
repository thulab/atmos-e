#!/usr/bin/env bash

# 提供可选生命周期钩子和标准阶段函数的统一调用入口。

# 若指定钩子已定义则调用，并向其转发全部参数。
run_hook() {
    local hook_name="$1"
    shift
    if declare -F "${hook_name}" >/dev/null 2>&1; then
        "${hook_name}" "$@"
    fi
}

# 按顺序执行阶段前置钩子、阶段实现及后置钩子。
run_phase() {
    local phase="$1"
    shift

    run_hook "before_${phase}" "$@" || return $?
    if declare -F "${phase}" >/dev/null 2>&1; then
        "${phase}" "$@" || return $?
    fi
    run_hook "after_${phase}" "$@"
}
