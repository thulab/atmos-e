#!/usr/bin/env bash

iotdb_prepare() { set_env; }
iotdb_apply_profile() { modify_iotdb_config; }
iotdb_set_protocol() { set_protocol_class "$1"; }
iotdb_start() { start_iotdb; }
iotdb_wait_ready() { wait_for_iotdb_ready; }
iotdb_exec() {
    local sql="$1"
    shift
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" "$@" -e "${sql}"
}
iotdb_flush() { iotdb_exec flush >/dev/null 2>&1; }
iotdb_stop() { stop_iotdb; }
iotdb_collect_runtime() { collect_runtime_metrics; }
