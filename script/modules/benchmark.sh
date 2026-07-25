#!/usr/bin/env bash

benchmark_prepare() { :; }
benchmark_install_case_config() { copy_benchmark_config "$1"; }
benchmark_start() { start_benchmark; }
benchmark_wait() { monitor_test_status "$@"; }
benchmark_find_result() { find_result_csv; }
benchmark_parse_result() {
    local kind="$1"
    shift
    case "${kind}" in
        ingestion) parse_ingestion_result "$@" ;;
        query) parse_query_result "$@" ;;
        *) return 20 ;;
    esac
}
benchmark_stop() { check_benchmark_pid; }
