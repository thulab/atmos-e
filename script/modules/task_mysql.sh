#!/usr/bin/env bash

# 将任务生命周期接口映射到 MySQL 任务状态操作。

# 从任务表认领下一条待测提交。
task_claim() { fetch_next_commit; }
# 将当前任务状态更新为运行中。
task_mark_running() { update_task_status "ontesting"; }
# 将当前任务状态更新为成功完成。
task_finish_success() { update_task_status "done"; }
# 将当前任务状态更新为失败。
task_finish_failure() { update_task_status "RError"; }
# 将较早的未处理提交标记为跳过。
task_skip_older() { mark_older_commits_skip; }

# 将当前提交元数据复制到任务上下文。
task_context_capture() {
    TASK_CTX[commit_id]="${commit_id:-}"
    TASK_CTX[author]="${author:-}"
    TASK_CTX[commit_date_time]="${commit_date_time:-}"
}
