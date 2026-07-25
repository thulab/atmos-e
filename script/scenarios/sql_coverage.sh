#!/usr/bin/env bash
set -u
set -o pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/scenarios/sql_coverage.sh"
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
