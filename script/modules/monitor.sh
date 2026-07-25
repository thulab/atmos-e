#!/usr/bin/env bash

monitor_collect() {
    if declare -F collect_monitor_data >/dev/null 2>&1; then
        collect_monitor_data "${TEST_IP:-}"
    fi
}

monitor_reset() {
    if declare -F init_common_items >/dev/null 2>&1; then
        init_common_items
    fi
}
