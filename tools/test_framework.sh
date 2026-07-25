#!/usr/bin/env bash
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

scenario_task_prepare() { :; }
scenario_task_claim() { TASK_CTX[commit_id]="test"; }
scenario_task_mark_running() { :; }
before_case_prepare() { OBSERVED_PHASES+=("case_prepare"); }
before_iotdb_prepare() { OBSERVED_PHASES+=("iotdb_prepare"); }
before_benchmark_execute() { OBSERVED_PHASES+=("benchmark_execute"); }
scenario_case_execute() { OBSERVED_CASES+=("${CASE_ID}"); }
scenario_task_finish_success() { :; }
scenario_task_finish_failure() { return 1; }

run_scenario
[ "${#OBSERVED_CASES[@]}" -eq 4 ]
[ "${#OBSERVED_PHASES[@]}" -eq 12 ]
[ "${OBSERVED_CASES[0]}" = "protocol=223__model=tree" ]
[ "${OBSERVED_CASES[3]}" = "protocol=224__model=table" ]

printf 'framework tests passed\n'
