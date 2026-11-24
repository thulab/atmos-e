#!/usr/bin/env bash
# 场景名称：双集群写入测试
# 测试目的：验证双集群环境下写入负载运行期间的数据处理和集群协同表现。
# 具体步骤：
# 步骤一：准备两个集群节点及远程执行环境。
# 步骤二：部署并启动双集群 IoTDB 服务。
# 步骤三：调用兼容场景实现执行写入测试。
# 步骤四：收集测试运行状态和结果数据。
# 步骤五：完成任务状态更新及测试现场收尾。
set -u
set -o pipefail

readonly SCENARIO_ID="cluster_insert_2"
readonly TASK_TEST_TYPE="cluster_insert_2"
readonly SCENARIO_FAILURE_POLICY="fail_fast"
readonly -a SCENARIO_CASE_DIMENSIONS=("type=cluster")

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/external.sh"
# 将任务准备阶段委托给外部场景适配器。
scenario_task_prepare() { external_scenario_prepare; }
# 将任务认领阶段委托给外部场景适配器。
scenario_task_claim() { external_scenario_claim; }
# 将运行状态标记阶段委托给外部场景适配器。
scenario_task_mark_running() { external_scenario_mark_running; }
# 启动双集群写入旧版实现脚本。
scenario_case_execute() { external_scenario_execute "${SCENARIO_DIR}/../modules/scenarios/cluster_insert_2_legacy.sh"; }
# 将成功收尾阶段委托给外部场景适配器。
scenario_task_finish_success() { external_scenario_finish; }
# 将失败收尾阶段委托给外部场景适配器。
scenario_task_finish_failure() { external_scenario_finish; }
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
