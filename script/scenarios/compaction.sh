#!/usr/bin/env bash
# 场景名称：IoTDB 压缩性能测试
# 测试目的：验证不同压缩配置下 IoTDB 压缩任务的性能表现和数据结果。
# 具体步骤：
# 步骤一：选择待测提交并准备 IoTDB 和测试运行环境。
# 步骤二：按用例配置部署并启动 IoTDB。
# 步骤三：执行压缩测试并采集压缩过程指标。
# 步骤四：解析测试结果并检查运行日志。
# 步骤五：将结果回写数据库并备份测试现场。
set -u
set -o pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/scenarios/compaction.sh"
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
