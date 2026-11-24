#!/usr/bin/env bash
# 场景名称：TsFile 工具性能测试
# 测试目的：比较 load-tsfile、export-tsfile 和 export-csv 在不同数据模型下的性能。
# 具体步骤：
# 步骤一：准备待测 IoTDB 版本、TsFile 数据集和工具配置。
# 步骤二：部署并启动 IoTDB，准备对应数据模型的 schema。
# 步骤三：执行 load-tsfile 导入测试并采集阶段指标。
# 步骤四：执行 export-tsfile 与 export-csv 导出测试。
# 步骤五：汇总阶段结果、回写数据库并备份测试现场。
set -u
set -o pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/scenarios/ts_performance.sh"
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
