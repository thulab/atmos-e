#!/usr/bin/env bash

external_scenario_prepare() { :; }
external_scenario_claim() { TASK_CTX[source]="external"; }
external_scenario_mark_running() { :; }
external_scenario_execute() {
    local implementation="$1"
    shift
    bash "${implementation}" "$@"
}
external_scenario_finish() { :; }
