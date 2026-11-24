#!/usr/bin/env bash

# 统一封装 IoTDB 环境准备、启动、SQL 执行、刷新和停止接口。

# 准备 IoTDB 测试环境。
iotdb_prepare() { set_env; }
# 应用当前测试所需的 IoTDB 配置。
iotdb_apply_profile() { modify_iotdb_config; }
# 设置当前测试使用的协议实现。
iotdb_set_protocol() { set_protocol_class "$1"; }
# 启动 IoTDB 服务。
iotdb_start() { start_iotdb; }
# 等待 IoTDB 服务就绪。
iotdb_wait_ready() { wait_for_iotdb_ready; }
# 通过 IoTDB CLI 执行 SQL 语句。
iotdb_exec() {
    local sql="$1"
    shift
    "${TEST_IOTDB_PATH}/sbin/start-cli.sh" "$@" -e "${sql}"
}
# 刷新 IoTDB 数据并隐藏命令输出。
iotdb_flush() { iotdb_exec flush >/dev/null 2>&1; }
# 停止 IoTDB 服务。
iotdb_stop() { stop_iotdb; }
# 收集 IoTDB 运行期指标。
iotdb_collect_runtime() { collect_runtime_metrics; }
