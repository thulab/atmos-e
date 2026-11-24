#!/usr/bin/env bash

# 校验场景声明，并将场景维度展开为可执行的用例集合。

# 检查场景必需字段、用例定义及失败策略是否合法。
scenario_validate_definition() {
    [ -n "${SCENARIO_ID:-}" ] || return 20
    [ -n "${TASK_TEST_TYPE:-}" ] || return 20
    if ! declare -p SCENARIO_CASE_DIMENSIONS >/dev/null 2>&1 &&
       ! declare -p SCENARIO_CASES >/dev/null 2>&1; then
        return 20
    fi
    case "${SCENARIO_FAILURE_POLICY:-continue_and_fail}" in
        fail_fast|continue_and_fail) ;;
        *) return 20 ;;
    esac
    run_hook scenario_validate
}

# 输出显式定义的用例，或按维度生成用例矩阵。
scenario_cases() {
    if declare -p SCENARIO_CASES >/dev/null 2>&1 && [ "${#SCENARIO_CASES[@]}" -gt 0 ]; then
        printf '%s\n' "${SCENARIO_CASES[@]}"
    else
        scenario_matrix "${SCENARIO_CASE_DIMENSIONS[@]}"
    fi
}

# 对逗号分隔的多个维度做笛卡尔积并输出用例行。
scenario_matrix() {
    local -a dimensions=("$@")
    local dimension=""
    local name=""
    local values=""
    local value=""
    local row=""
    local -a rows=("")
    local -a next_rows=()
    local -a dimension_values=()

    for dimension in "${dimensions[@]}"; do
        name="${dimension%%=*}"
        values="${dimension#*=}"
        [ -n "${name}" ] && [ "${dimension}" != "${name}" ] || return 20
        next_rows=()
        IFS=',' read -r -a dimension_values <<< "${values}"
        for row in "${rows[@]}"; do
            for value in "${dimension_values[@]}"; do
                [ -n "${value}" ] || continue
                next_rows+=("${row}${row:+$'\t'}${name}=${value}")
            done
        done
        rows=("${next_rows[@]}")
    done

    printf '%s\n' "${rows[@]}"
}
