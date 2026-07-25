#!/usr/bin/env bash

readonly FRAMEWORK_NO_TASK=10
readonly FRAMEWORK_CONFIG_ERROR=20
readonly FRAMEWORK_CASE_ERROR=50

readonly -a FRAMEWORK_CASE_PHASES=(
    case_prepare
    iotdb_prepare
    iotdb_configure
    iotdb_start
    benchmark_prepare
    benchmark_execute
    benchmark_wait
    result_parse
    monitor_collect
    result_persist
    runtime_stop
    case_backup
)

run_case() {
    local -a assignments=("$@")
    local status=0

    case_context_begin "${assignments[@]}" || return $?
    run_hook before_case || status=$?
    local phase=""
    for phase in "${FRAMEWORK_CASE_PHASES[@]}"; do
        if [ "${phase}" = "benchmark_execute" ] &&
           declare -F scenario_case_execute >/dev/null 2>&1 &&
           ! declare -F benchmark_execute >/dev/null 2>&1; then
            run_hook before_benchmark_execute || status=$?
            if [ "${status}" -eq 0 ]; then
                run_phase scenario_case_execute || status=$?
            fi
            if [ "${status}" -eq 0 ]; then
                run_hook after_benchmark_execute || status=$?
            fi
        else
            run_phase "${phase}" || status=$?
        fi
        [ "${status}" -eq 0 ] || break
    done
    if [ "${status}" -eq 1 ]; then
        status="${FRAMEWORK_CASE_ERROR}"
    fi
    if [ "${status}" -eq 0 ]; then
        CASE_CTX[status]="done"
    else
        CASE_CTX[status]="failed"
        RESULT_CTX[error_code]="${status}"
        run_hook on_case_failure "${status}" || true
    fi
    run_hook after_case "${status}" || [ "${status}" -ne 0 ] || status=$?
    case_context_finish
    return "${status}"
}

run_all_cases() {
    local matrix_row=""
    local status=0
    local failed=0
    local -a assignments=()

    while IFS= read -r matrix_row; do
        [ -n "${matrix_row}" ] || continue
        IFS=$'\t' read -r -a assignments <<< "${matrix_row}"
        run_case "${assignments[@]}" || status=$?
        if [ "${status}" -ne 0 ]; then
            failed=1
            RUN_CTX[failed_cases]=$((${RUN_CTX[failed_cases]:-0} + 1))
            RUN_CTX[error_code]="${status}"
            [ "${SCENARIO_FAILURE_POLICY:-continue_and_fail}" = "fail_fast" ] && break
        fi
    done < <(scenario_cases)

    [ "${failed}" -eq 0 ]
}

run_task() {
    local status=0

    run_hook before_task || return $?
    scenario_task_prepare || return $?
    scenario_task_claim || return "${FRAMEWORK_NO_TASK}"
    run_phase scenario_task_mark_running || return $?
    run_context_begin
    run_hook before_run || status=$?
    if [ "${status}" -eq 0 ]; then
        run_all_cases || status="${RUN_CTX[error_code]:-${FRAMEWORK_CASE_ERROR}}"
    fi
    run_hook after_run "${status}" || [ "${status}" -ne 0 ] || status=$?

    if [ "${status}" -eq 0 ]; then
        RUN_CTX[status]="done"
        scenario_task_finish_success || status=$?
    else
        RUN_CTX[status]="failed"
        RUN_CTX[error_code]="${status}"
        scenario_task_finish_failure "${status}" || true
        run_hook on_task_failure "${status}" || true
    fi
    run_hook after_task "${status}" || [ "${status}" -ne 0 ] || status=$?
    return "${status}"
}
