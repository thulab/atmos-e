#!/usr/bin/env bash
set -u
set -o pipefail

readonly TEST_IP="172.20.31.5"
readonly TEST_TYPE="se_insert"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/insert_common.sh
source "${SCRIPT_DIR}/insert_common.sh"

main "$@"
