#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="172.20.31.29"
readonly TEST_TYPE="api_insert_cts"
readonly -a PROTOCOL_LIST=(223)
readonly -a TS_LIST=(tempaligned)
readonly -a API_LIST=(SESSION_BY_TABLET SESSION_BY_RECORDS SESSION_BY_RECORD JDBC)
readonly ENABLE_BENCHMARK_VERSION_CHECK=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/insert_common.sh
source "${SCRIPT_DIR}/insert_common.sh"

main "$@"
