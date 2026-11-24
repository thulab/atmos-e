#!/usr/bin/env bash
# 框架生命周期与矩阵展开的轻量回归测试脚本。
set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/script/framework/runner.sh"

SCENARIO_ID="framework_test"
TASK_TEST_TYPE="framework_test"
SCENARIO_FAILURE_POLICY="continue_and_fail"
SCENARIO_CASE_DIMENSIONS=("protocol=223,224" "model=tree,table")

declare -a OBSERVED_CASES=()
declare -a OBSERVED_PHASES=()

# 模拟任务准备阶段。
scenario_task_prepare() { :; }
# 设置测试任务提交标识并模拟认领成功。
scenario_task_claim() { TASK_CTX[commit_id]="test"; }
# 模拟任务进入运行状态。
scenario_task_mark_running() { :; }
# 记录用例准备阶段被调用。
before_case_prepare() { OBSERVED_PHASES+=("case_prepare"); }
# 记录 IoTDB 准备阶段被调用。
before_iotdb_prepare() { OBSERVED_PHASES+=("iotdb_prepare"); }
# 记录 Benchmark 执行阶段被调用。
before_benchmark_execute() { OBSERVED_PHASES+=("benchmark_execute"); }
# 记录框架派发的用例标识。
scenario_case_execute() { OBSERVED_CASES+=("${CASE_ID}"); }
# 模拟任务成功收尾。
scenario_task_finish_success() { :; }
# 模拟任务失败收尾并返回错误。
scenario_task_finish_failure() { return 1; }

run_scenario
[ "${#OBSERVED_CASES[@]}" -eq 4 ]
[ "${#OBSERVED_PHASES[@]}" -eq 12 ]
[ "${OBSERVED_CASES[0]}" = "protocol=223__model=tree" ]
[ "${OBSERVED_CASES[3]}" = "protocol=224__model=table" ]

printf 'framework tests passed\n'
