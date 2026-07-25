#!/usr/bin/env bash

notification_send() {
    if declare -F sendMsg >/dev/null 2>&1; then
        sendMsg "$@"
    elif declare -F sendEmail >/dev/null 2>&1; then
        sendEmail "$@"
    else
        return 0
    fi
}
