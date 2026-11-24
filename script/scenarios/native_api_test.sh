#!/usr/bin/env bash
# 场景名称：原生 API 兼容性测试
# 测试目的：验证 IoTDB 原生 API 在指定运行环境中的调用和测试兼容性。
# 具体步骤：
# 步骤一：准备待测版本、原生 API 测试工具及运行环境。
# 步骤二：部署并启动 IoTDB 服务。
# 步骤三：调用兼容实现执行原生 API 测试。
# 步骤四：采集测试输出并判断执行状态。
# 步骤五：完成任务状态更新和测试现场收尾。
set -u
set -o pipefail

readonly SCENARIO_ID="native_api_test"
readonly TASK_TEST_TYPE="native_api_test"
readonly SCENARIO_FAILURE_POLICY="fail_fast"
readonly -a SCENARIO_CASE_DIMENSIONS=("type=native_api")

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/external.sh"
# 将任务准备阶段委托给外部场景适配器。
scenario_task_prepare() { external_scenario_prepare; }
# 将任务认领阶段委托给外部场景适配器。
scenario_task_claim() { external_scenario_claim; }
# 将运行状态标记阶段委托给外部场景适配器。
scenario_task_mark_running() { external_scenario_mark_running; }
# 启动原生 API 测试的兼容实现脚本。
scenario_case_execute() { external_scenario_execute "${SCENARIO_DIR}/../modules/scenarios/native_api_test_legacy.sh"; }
# 将成功收尾阶段委托给外部场景适配器。
scenario_task_finish_success() { external_scenario_finish; }
# 将失败收尾阶段委托给外部场景适配器。
scenario_task_finish_failure() { external_scenario_finish; }
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
