#!/usr/bin/env bash
# 场景名称：顺序数据查询测试
# 测试目的：验证顺序数据集在多类查询语句下的查询性能和结果稳定性。
# 具体步骤：
# 步骤一：选择待测 IoTDB 版本并准备顺序查询数据集。
# 步骤二：部署 IoTDB，加载查询配置和数据后启动服务。
# 步骤三：按查询类型启动 benchmark 执行查询压测。
# 步骤四：采集查询耗时、资源监控指标和错误日志。
# 步骤五：将测试结果回写数据库并备份测试现场。
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_IP="172.20.31.12"
readonly TEST_TYPE="se_query"
readonly DATA_PATH="/nasdata/se_query/DataSet"
readonly IOTDB_PW="root"
readonly -a PROTOCOL_LIST=(211)
readonly -a QUERY_DATA_TYPES=(tablemode common aligned tempaligned)
readonly -a QUERY_LIST=(
    Q1 Q2-1 Q2-2 Q2-3 Q3-1 Q3-2 Q3-3 Q4a-1 Q4a-2 Q4a-3
    Q4b-1 Q4b-2 Q4b-3 Q5 Q6-1 Q6-2 Q6-3 Q7-1 Q7-2 Q7-3
    Q8 Q9-1 Q9-2 Q9-3 Q10
)
readonly -a QUERY_LABELS=(
    PRECISE_POINT TIME_RANGE TIME_RANGE TIME_RANGE VALUE_RANGE VALUE_RANGE VALUE_RANGE
    AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_RANGE AGG_VALUE
    AGG_RANGE_VALUE AGG_RANGE_VALUE AGG_RANGE_VALUE GROUP_BY GROUP_BY GROUP_BY
    LATEST_POINT RANGE_QUERY_DESC RANGE_QUERY_DESC RANGE_QUERY_DESC VALUE_RANGE_QUERY_DESC
)
readonly METRIC_SERVER="172.20.70.11:9090"
IOTDB_READY_PASSWORD="${IOTDB_PW}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/../common" && pwd)"
# shellcheck source=script/common/query_common.sh
source "${COMMON_DIR}/query_common.sh"

main "$@"
