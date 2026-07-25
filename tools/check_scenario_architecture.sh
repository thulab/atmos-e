#!/usr/bin/env bash
set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO_DIR="${ROOT}/script/scenarios"
failed=0

check_forbidden() {
    local label="$1"
    local pattern="$2"
    local matches=""
    matches="$(grep -En "${pattern}" "${SCENARIO_DIR}"/*.sh || true)"
    if [ -n "${matches}" ]; then
        printf 'forbidden scenario operation (%s):\n%s\n' "${label}" "${matches}" >&2
        failed=1
    fi
}

check_forbidden "recursive delete" '(^|[[:space:]])rm[[:space:]]+-rf'
check_forbidden "direct IoTDB CLI" 'start-cli\.sh'
check_forbidden "direct IoTDB process start" 'start-(confignode|datanode)\.sh'
check_forbidden "direct task status SQL" 'update.*(done|skip|RError|ontesting)'
check_forbidden "direct benchmark start" '(^|[/[:space:]])benchmark\.sh'
check_forbidden "direct result SQL" 'insert[[:space:]]+into'

while IFS= read -r scenario; do
    grep -q 'run_scenario' "${scenario}" || {
        printf 'scenario does not use framework runner: %s\n' "${scenario}" >&2
        failed=1
    }
done < <(find "${SCENARIO_DIR}" -maxdepth 1 -type f -name '*.sh' | sort)

exit "${failed}"
