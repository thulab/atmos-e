#!/usr/bin/env bash
COMMON_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/common/iotdb_config_common.sh
source "${COMMON_WRAPPER_DIR}/common/iotdb_config_common.sh"
