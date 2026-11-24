#!/usr/bin/env bash

# 统一封装 Benchmark 配置、启动、等待、结果解析和停止接口。

# 执行 Benchmark 阶段的预留准备钩子。
benchmark_prepare() { :; }
# 安装当前用例对应的 Benchmark 配置。
benchmark_install_case_config() { copy_benchmark_config "$1"; }
# 启动 Benchmark 测试进程。
benchmark_start() { start_benchmark; }
# 等待 Benchmark 测试完成并监控执行状态。
benchmark_wait() { monitor_test_status "$@"; }
# 查找 Benchmark 输出的结果 CSV。
benchmark_find_result() { find_result_csv; }
# 按结果类型调用对应的解析函数。
benchmark_parse_result() {
    local kind="$1"
    shift
    case "${kind}" in
        ingestion) parse_ingestion_result "$@" ;;
        query) parse_query_result "$@" ;;
        *) return 20 ;;
    esac
}
# 停止或清理 Benchmark 测试进程。
benchmark_stop() { check_benchmark_pid; }
