#!/usr/bin/env bash
COMMON_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/common/monitor_disk_common.sh
source "${COMMON_WRAPPER_DIR}/common/monitor_disk_common.sh"
