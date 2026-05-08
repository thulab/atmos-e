#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="172.20.31.32"
readonly TEST_TYPE="weeklytest_insert"
readonly -a PROTOCOL_LIST=(223)
readonly -a TS_LIST=(
    tempaligned_seq_w
    tempaligned_unseq_w
    tablemode_seq_w
    tablemode_unseq_w
)
readonly -a API_LIST=(SESSION_BY_TABLET)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/insert_common.sh
source "${SCRIPT_DIR}/insert_common.sh"

main "$@"
