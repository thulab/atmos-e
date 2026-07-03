#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "task_db_common.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "task_db_common.sh requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi

task_status_table_name() {
    local table_name="${TASK_TABLENAME:-${TASK_TABLE_NAME:-}}"

    [ -n "${table_name}" ] || die "missing task status table name"
    printf '%s\n' "${table_name}"
}

task_status_query_exec() {
    local sql="$1"

    if [ "${TASK_DB_SUPPRESS_QUERY_ERRORS:-0}" = "1" ]; then
        mysql_exec "${sql}" 2>/dev/null || true
    else
        mysql_exec "${sql}"
    fi
}

update_task_status() {
    local status="$1"
    local table_name=""

    table_name="$(task_status_table_name)"
    mysql_exec "update ${table_name} set ${TEST_TYPE} = $(sql_quote "${status}") where commit_id = $(sql_quote "${commit_id}")"
}

mark_older_commits_skip() {
    local table_name=""

    table_name="$(task_status_table_name)"
    mysql_exec "update ${table_name} set ${TEST_TYPE} = 'skip' where ${TEST_TYPE} is NULL and commit_date_time < $(sql_quote "${commit_date_time}")"
}

query_next_commit() {
    local status_filter="$1"
    local table_name=""

    table_name="$(task_status_table_name)"
    if [ "${status_filter}" = "retest" ]; then
        task_status_query_exec "SELECT commit_id, author, commit_date_time FROM ${table_name} WHERE ${TEST_TYPE} = 'retest' ORDER BY commit_date_time desc LIMIT 1"
    else
        task_status_query_exec "SELECT commit_id, author, commit_date_time FROM ${table_name} WHERE ${TEST_TYPE} is NULL ORDER BY commit_date_time desc LIMIT 1"
    fi
}

fetch_next_commit() {
    local row=""
    local raw_commit_date_time=""

    row="$(query_next_commit "retest")"
    if [ -z "${row}" ]; then
        row="$(query_next_commit "pending")"
    fi
    [ -n "${row}" ] || return 1

    IFS=$'\t' read -r commit_id author raw_commit_date_time <<< "${row}"
    author="$(trim "${author}")"
    commit_date_time="$(normalize_datetime "${raw_commit_date_time}")"
    [ -n "${commit_id}" ] || return 1
    [ -n "${commit_date_time}" ] || die "${TASK_DB_PARSE_ERROR_MESSAGE:-commit_date_time parse failed}"
}
