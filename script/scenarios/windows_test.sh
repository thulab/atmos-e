#!/usr/bin/env bash
# 场景名称：Windows 测试场景
# 测试目的：验证 Windows 兼容场景下常规写入和查询用例的执行及结果采集。
# 具体步骤：
# 步骤一：选择待测 IoTDB 版本并准备测试配置。
# 步骤二：部署 IoTDB 并按协议配置启动服务。
# 步骤三：执行写入用例并刷新测试数据。
# 步骤四：执行查询用例并收集结果和监控指标。
# 步骤五：回写测试结果并备份运行现场。
set -u
set -o pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/scenarios/windows_test.sh"
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
