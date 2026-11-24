#!/usr/bin/env bash

# 管理任务、运行和用例上下文，并在用例生命周期中同步维度字段。

declare -gA TASK_CTX=()
declare -gA RUN_CTX=()
declare -gA CASE_CTX=()
declare -gA RESULT_CTX=()

# 清空当前任务、运行、用例及结果上下文。
context_reset() {
    TASK_CTX=()
    RUN_CTX=()
    CASE_CTX=()
    RESULT_CTX=()
}

# 初始化一次运行的标识、开始时间、状态和失败用例计数。
run_context_begin() {
    RUN_CTX[id]="$(date '+%Y%m%d%H%M%S')-$$"
    RUN_CTX[start_time]="$(date '+%Y-%m-%d %H:%M:%S')"
    RUN_CTX[status]="running"
    RUN_CTX[failed_cases]=0
}

# 根据键值维度初始化用例上下文，并导出常用维度变量。
case_context_begin() {
    local assignment=""
    local key=""
    local value=""
    local id=""

    CASE_CTX=()
    RESULT_CTX=()
    for assignment in "$@"; do
        key="${assignment%%=*}"
        value="${assignment#*=}"
        [ -n "${key}" ] && [ "${assignment}" != "${key}" ] || return 20
        CASE_CTX["${key}"]="${value}"
        if [ -n "${id}" ]; then
            id="${id}__"
        fi
        id="${id}${key}=${value}"
    done

    CASE_CTX[id]="${id}"
    CASE_CTX[status]="running"
    CASE_CTX[start_time]="$(date '+%Y-%m-%d %H:%M:%S')"

    CASE_ID="${CASE_CTX[id]}"
    CASE_PROTOCOL="${CASE_CTX[protocol]:-}"
    CASE_CASE="${CASE_CTX[case]:-}"
    CASE_MODEL="${CASE_CTX[model]:-}"
    CASE_WORKLOAD="${CASE_CTX[workload]:-}"
    CASE_API="${CASE_CTX[api]:-}"
    CASE_QUERY="${CASE_CTX[query]:-}"
    CASE_DATA_TYPE="${CASE_CTX[data_type]:-}"
    CASE_MODE="${CASE_CTX[mode]:-}"
    CASE_TYPE="${CASE_CTX[type]:-}"
    CASE_ATTEMPT="${CASE_CTX[attempt]:-1}"
}

# 记录当前用例的结束时间。
case_context_finish() {
    CASE_CTX[end_time]="$(date '+%Y-%m-%d %H:%M:%S')"
}
