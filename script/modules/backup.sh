#!/usr/bin/env bash

backup_case_path() {
    build_scoped_path "${BACKUP_PATH}" "$@"
}

backup_runtime() {
    local target="$1"
    archive_test_runtime_artifacts "${target}"
}
