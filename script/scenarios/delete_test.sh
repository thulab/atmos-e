#!/usr/bin/env bash
# 场景名称：数据删除测试
# 测试目的：验证 IoTDB 在不同协议和数据条件下执行删除操作的正确性与性能。
# 具体步骤：
# 步骤一：选择待测提交并准备 IoTDB、Benchmark 及测试数据。
# 步骤二：部署并启动 IoTDB，加载删除测试配置。
# 步骤三：执行删除测试并监控服务运行状态。
# 步骤四：解析删除结果、资源指标和错误日志。
# 步骤五：将测试结果回写数据库并备份测试现场。
set -u
set -o pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/scenarios/delete_test.sh"
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
