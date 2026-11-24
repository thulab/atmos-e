#!/usr/bin/env bash

# 提供将任务生命周期委托给外部脚本执行的适配器。

# 执行外部场景准备阶段的空操作适配。
external_scenario_prepare() { :; }
# 标记任务来源为外部场景。
external_scenario_claim() { TASK_CTX[source]="external"; }
# 执行外部场景运行状态标记的空操作适配。
external_scenario_mark_running() { :; }
# 以独立 Bash 进程运行指定的外部实现脚本。
external_scenario_execute() {
    local implementation="$1"
    shift
    bash "${implementation}" "$@"
}
# 执行外部场景完成阶段的空操作适配。
external_scenario_finish() { :; }
