#!/usr/bin/env bash
# 场景名称：Pipe 双节点同步测试
# 测试目的：验证两个 IoTDB 节点之间 Pipe 创建、启动、数据同步和一致性表现。
# 具体步骤：
# 步骤一：准备两台远端节点的 IoTDB 和 benchmark 运行环境。
# 步骤二：部署并启动源端和目标端 IoTDB。
# 步骤三：创建 Pipe，启动源端 benchmark 写入数据。
# 步骤四：监控同步进度并校验两端设备和点数一致性。
# 步骤五：采集节点指标，将结果回写数据库并备份测试现场。
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/../common" && pwd)"
# shellcheck source=script/common/pipe_common.sh
source "${COMMON_DIR}/pipe_common.sh"

main "$@"
