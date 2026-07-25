#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "framework requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "framework requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi

FRAMEWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${FRAMEWORK_ROOT}/context.sh"
source "${FRAMEWORK_ROOT}/hooks.sh"
source "${FRAMEWORK_ROOT}/scenario.sh"
source "${FRAMEWORK_ROOT}/lifecycle.sh"

run_scenario() {
    local status=0

    context_reset
    scenario_validate_definition || {
        printf 'invalid scenario definition: %s\n' "${SCENARIO_ID:-<unset>}" >&2
        return 20
    }
    run_task || status=$?
    [ "${status}" -eq "${FRAMEWORK_NO_TASK}" ] && return 0
    return "${status}"
}
