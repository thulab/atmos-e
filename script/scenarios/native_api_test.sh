#!/usr/bin/env bash
set -u
set -o pipefail

readonly SCENARIO_ID="native_api_test"
readonly TASK_TEST_TYPE="native_api_test"
readonly SCENARIO_FAILURE_POLICY="fail_fast"
readonly -a SCENARIO_CASE_DIMENSIONS=("type=native_api")

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/external.sh"
scenario_task_prepare() { external_scenario_prepare; }
scenario_task_claim() { external_scenario_claim; }
scenario_task_mark_running() { external_scenario_mark_running; }
scenario_case_execute() { external_scenario_execute "${SCENARIO_DIR}/../modules/scenarios/native_api_test_legacy.sh"; }
scenario_task_finish_success() { external_scenario_finish; }
scenario_task_finish_failure() { external_scenario_finish; }
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
