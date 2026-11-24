#!/usr/bin/env bash

# 提供测试用例备份路径生成及运行产物归档接口。

# 按备份根目录和用例维度生成备份路径。
backup_case_path() {
    build_scoped_path "${BACKUP_PATH}" "$@"
}

# 将测试运行日志和临时产物归档到指定目录。
backup_runtime() {
    local target="$1"
    archive_test_runtime_artifacts "${target}"
}
