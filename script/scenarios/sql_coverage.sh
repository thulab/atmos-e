#!/usr/bin/env bash
# 场景名称：SQL 覆盖率测试
# 测试目的：验证 SQL 测试套件在目标 IoTDB 版本上的通过情况和覆盖表现。
# 具体步骤：
# 步骤一：准备待测版本、SQL 测试用例仓库及运行依赖。
# 步骤二：部署并启动 IoTDB，准备测试工具和执行账户。
# 步骤三：按配置模式编译并运行 SQL 测试套件。
# 步骤四：监控测试进度并解析通过、失败用例数。
# 步骤五：持久化测试结果并备份运行现场。
set -u
set -o pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../modules/scenarios/sql_coverage.sh"
source "${SCENARIO_DIR}/../framework/runner.sh"
run_scenario "$@"
