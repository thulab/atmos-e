#!/usr/bin/env bash

run_hook() {
    local hook_name="$1"
    shift
    if declare -F "${hook_name}" >/dev/null 2>&1; then
        "${hook_name}" "$@"
    fi
}

run_phase() {
    local phase="$1"
    shift

    run_hook "before_${phase}" "$@" || return $?
    if declare -F "${phase}" >/dev/null 2>&1; then
        "${phase}" "$@" || return $?
    fi
    run_hook "after_${phase}" "$@"
}
