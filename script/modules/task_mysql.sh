#!/usr/bin/env bash

task_claim() { fetch_next_commit; }
task_mark_running() { update_task_status "ontesting"; }
task_finish_success() { update_task_status "done"; }
task_finish_failure() { update_task_status "RError"; }
task_skip_older() { mark_older_commits_skip; }

task_context_capture() {
    TASK_CTX[commit_id]="${commit_id:-}"
    TASK_CTX[author]="${author:-}"
    TASK_CTX[commit_date_time]="${commit_date_time:-}"
}
