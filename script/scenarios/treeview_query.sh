#!/usr/bin/env bash
# 场景名称：TreeView 查询测试
# 测试目的：验证树模型数据映射至表模型视图后的查询能力和性能表现。
# 具体步骤：
# 步骤一：准备待测 IoTDB 版本及树模型查询数据集。
# 步骤二：部署并启动 IoTDB，创建 TreeView 映射配置。
# 步骤三：按查询套件执行 Benchmark 查询负载。
# 步骤四：采集查询结果、运行日志和资源指标。
# 步骤五：回写查询结果并备份测试现场。
set -u
set -o pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/scenarios/treeview_query.sh"
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
