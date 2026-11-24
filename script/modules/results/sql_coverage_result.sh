#!/usr/bin/env bash

# 提供 SQL 覆盖测试结果的统一写入器。

# 将参数转发给当前场景的结果行写入实现。
result_write_sql_coverage() { insert_result_row "$@"; }
