#!/usr/bin/env bash

# 按可用通知实现发送测试消息。

# 优先调用 sendMsg，其次回退到 sendEmail。
notification_send() {
    if declare -F sendMsg >/dev/null 2>&1; then
        sendMsg "$@"
    elif declare -F sendEmail >/dev/null 2>&1; then
        sendEmail "$@"
    else
        return 0
    fi
}
