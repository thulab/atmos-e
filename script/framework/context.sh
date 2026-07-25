#!/usr/bin/env bash

declare -gA TASK_CTX=()
declare -gA RUN_CTX=()
declare -gA CASE_CTX=()
declare -gA RESULT_CTX=()

context_reset() {
    TASK_CTX=()
    RUN_CTX=()
    CASE_CTX=()
    RESULT_CTX=()
}

run_context_begin() {
    RUN_CTX[id]="$(date '+%Y%m%d%H%M%S')-$$"
    RUN_CTX[start_time]="$(date '+%Y-%m-%d %H:%M:%S')"
    RUN_CTX[status]="running"
    RUN_CTX[failed_cases]=0
}

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

case_context_finish() {
    CASE_CTX[end_time]="$(date '+%Y-%m-%d %H:%M:%S')"
}
