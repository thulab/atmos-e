#!/usr/bin/env bash

init_items() {
    commit_date_time=0
    commit_id=0
    author=0
    se_insert=0
    unse_insert=0
    se_query=0
    unse_query=0
    compaction=0
    sql_coverage=0
    weeklytest_insert=0
    weeklytest_query=0
    api_insert=0
    ts_performance=0
    cluster_insert=0
    cluster_insert_2=0
    insert_records=0
    restart_db=0
    routine_test=0
    config_insert=0
    count_ts=0
    pipe_test=0
    last_cache_query=0
    windows_test=0
    benchants=0
    helishi_test=0
    remark=0
}

sendEmail() {
    error_type=$1
    date_time=$(date +%Y%m%d%H%M%S)
    mailto='qingxin.feng@hotmail.com'
    test_type=${HOSTNAME}
    case ${error_type} in
        1)
            headline="${test_type}代码更新失败"
            mailbody="错误类型：${test_type}代码更新失败<BR>报错时间：${date_time}"
            msgbody="错误类型：${test_type}代码更新失败\n报错时间：${date_time}"
            ;;
        2)
            headline="${test_type}代码编译失败"
            mailbody="错误类型：${test_type}代码编译失败<BR>报错时间：${date_time}<BR>报错Commit：${commit_id}<BR>提交人：${author}"
            msgbody="错误类型：${test_type}代码编译失败\n报错时间：${date_time}\n报错Commit：${commit_id}\n<BR>提交人：${author}"
            ;;
    esac
    curl 'https://oapi.dingtalk.com/robot/send?access_token=f2d691d45da9a0307af8bbd853e90d0785dbaa3a3b0219dd2816882e19859e62' \
        -H 'Content-Type: application/json' \
        -d '{"msgtype": "text","text": {"content": "[Atmos]'"${msgbody}"'"}}' >/dev/null 2>&1 &
}
