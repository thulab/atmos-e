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
readonly -a PROTOCOL_LIST=(223 224)
readonly -a INSERT_CASE_LIST=(
    "tempaligned|seq_w|SESSION_BY_TABLET"
    "tempaligned|unseq_w|SESSION_BY_TABLET"
    "tempaligned|seq_rw|SESSION_BY_TABLET"
    "tablemode|seq_w|SESSION_BY_TABLET"
    "tablemode|unseq_w|SESSION_BY_TABLET"
    "tablemode|seq_rw|SESSION_BY_TABLET"
)
readonly -a API_LIST=(SESSION_BY_TABLET)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/insert_common.sh
source "${SCRIPT_DIR}/insert_common.sh"

main "$@"
