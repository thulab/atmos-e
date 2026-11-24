#!/usr/bin/env bash

# 提供监控数据采集和监控状态重置模块接口。

# 调用场景提供的监控函数采集当前节点数据。
monitor_collect() {
    if declare -F collect_monitor_data >/dev/null 2>&1; then
        collect_monitor_data "${TEST_IP:-}"
    fi
}

# 若存在初始化函数则重置公共监控状态。
monitor_reset() {
    if declare -F init_common_items >/dev/null 2>&1; then
        init_common_items
    fi
}
