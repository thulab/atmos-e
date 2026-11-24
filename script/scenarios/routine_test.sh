#!/usr/bin/env bash
# 场景名称：常规读写测试
# 测试目的：验证常规写入与查询负载组合下 IoTDB 的功能及性能表现。
# 具体步骤：
# 步骤一：选择待测版本并准备写入、查询配置及数据集。
# 步骤二：部署并启动 IoTDB，设置当前用例所需参数。
# 步骤三：执行写入负载并刷新数据。
# 步骤四：执行查询套件并采集结果和监控数据。
# 步骤五：汇总结果、回写数据库并备份测试现场。
set -u
set -o pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/scenarios/routine_test.sh"
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
