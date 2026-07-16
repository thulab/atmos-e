#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

ACCOUNT="${ACCOUNT:-root}"
test_type="compile"

INIT_PATH="${INIT_PATH:-/root/zk_test}"
IOTDB_PATH="${IOTDB_PATH:-${INIT_PATH}/timechodb}"
FILENAME="${FILENAME:-${INIT_PATH}/gitlog.txt}"
REPO_PATH="${REPO_PATH:-/nasdata/repository/master}"
REPO_PATH_EX="${REPO_PATH_EX:-/ex_nasdata/repository/master}"
IOTDB_REMOTE="${IOTDB_REMOTE:-origin}"
IOTDB_BRANCH="${IOTDB_BRANCH:-master}"
COMPILE_COMMIT_WINDOW="${COMPILE_COMMIT_WINDOW:-11}"
COMPILE_COMMIT_ID_LENGTH="${COMPILE_COMMIT_ID_LENGTH:-8}"
COMPILE_MVN_ARGS="${COMPILE_MVN_ARGS:-clean package -DskipTests -am -pl distribution}"
COMPILE_REPLAN_EXISTING="${COMPILE_REPLAN_EXISTING:-1}"

MYSQLHOSTNAME="${MYSQLHOSTNAME:-111.200.37.158}"
PORT="${PORT:-13306}"
USERNAME="${USERNAME:-iotdbatm}"
PASSWORD="${ATMOS_DB_PASSWORD:-}"
DBNAME="${DBNAME:-QA_ATM}"
TABLENAME="${TABLENAME:-commit_history}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATMOS_PATH="${ATMOS_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
COMMON_DIR="${ATMOS_PATH}/script/common"
# shellcheck source=script/common/shell_common.sh
source "${COMMON_DIR}/shell_common.sh"
# shellcheck source=script/common/precise_test_common.sh
source "${COMMON_DIR}/precise_test_common.sh"

COMPILE_STATUS_COLUMNS=(
    "${PRECISE_TEST_STATUS_COLUMNS[@]}"
    insert_records
    restart_db
    count_ts
    last_cache_query
)

ensure_dependencies() {
    require_commands awk cp curl cut date find git mkdir mysql rm sed timeout tr mvn
}

sendEmail() {
    local error_type="$1"
    local date_time=""
    local msgbody=""

    date_time="$(date +%Y%m%d%H%M%S)"
    case "${error_type}" in
        1)
            msgbody="Error type: ${test_type} code update failed\nTime: ${date_time}"
            ;;
        2)
            msgbody="Error type: ${test_type} compile failed\nTime: ${date_time}\nCommit: ${commit_id:-N/A}\nAuthor: ${author:-N/A}"
            ;;
        *)
            msgbody="Error type: ${test_type} unknown failure\nTime: ${date_time}"
            ;;
    esac

    curl 'https://oapi.dingtalk.com/robot/send?access_token=f2d691d45da9a0307af8bbd853e90d0785dbaa3a3b0219dd2816882e19859e62' \
        -H 'Content-Type: application/json' \
        -d '{"msgtype": "text","text": {"content": "[Atmos]'"${msgbody}"'"}}' >/dev/null 2>&1 &
}

sync_source_repo() {
    [ -d "${IOTDB_PATH}/.git" ] || die "IOTDB_PATH is not a git repo: ${IOTDB_PATH}"

    cd "${IOTDB_PATH}" || die "failed to cd to ${IOTDB_PATH}"
    timeout 100s git fetch --all || {
        sendEmail 1
        die "git fetch failed"
    }
    timeout 100s git reset --hard "${IOTDB_REMOTE}/${IOTDB_BRANCH}" || {
        sendEmail 1
        die "git reset failed: ${IOTDB_REMOTE}/${IOTDB_BRANCH}"
    }
    timeout 100s git pull --ff-only "${IOTDB_REMOTE}" "${IOTDB_BRANCH}" || {
        sendEmail 1
        die "git pull failed: ${IOTDB_REMOTE} ${IOTDB_BRANCH}"
    }
}

shorten_commit_id() {
    local raw_commit="$1"

    printf '%s\n' "${raw_commit}" | cut -c1-"${COMPILE_COMMIT_ID_LENGTH}"
}

commit_exists() {
    local current_commit="$1"
    local result=""

    result="$(mysql_exec "SELECT commit_id FROM ${TABLENAME} WHERE commit_id = $(sql_quote "${current_commit}") LIMIT 1" | sed -n '1p')"
    [ -n "${result}" ]
}

replan_existing_commit() {
    local target_commit="$1"

    [ "${COMPILE_REPLAN_EXISTING}" = "1" ] || return 0

    cd "${IOTDB_PATH}" || die "failed to cd to ${IOTDB_PATH}"
    timeout 100s git reset --hard "${target_commit}" || die "failed to reset to existing commit ${target_commit}"
    load_commit_metadata
    PRECISE_TEST_REPO_PATH="${IOTDB_PATH}" apply_precise_test_plan "${commit_id}" "${commit_date_time}" "${author}"
    log "commit ${commit_id} precise test plan refreshed"
}

insert_commit_record() {
    local status="$1"
    local insert_sql=""

    insert_sql="INSERT INTO ${TABLENAME} (commit_date_time, commit_id, author, remark)
        VALUES (${commit_date_time}, $(sql_quote "${commit_id}"), $(sql_quote "${author}"), $(sql_quote "${commit_headline}"))"

    mysql_exec "${insert_sql}" >/dev/null || return 1

    if [ -n "${status}" ]; then
        update_existing_status_columns "${commit_id}" "${status}"
    fi
}

update_existing_status_columns() {
    local current_commit="$1"
    local status="$2"
    local column=""

    for column in "${COMPILE_STATUS_COLUMNS[@]}"; do
        [[ "${column}" =~ ^[A-Za-z0-9_]+$ ]] || continue
        precise_column_exists "${TABLENAME}" "${column}" || continue
        mysql_exec "UPDATE ${TABLENAME} SET \`${column}\` = $(sql_quote "${status}") WHERE commit_id = $(sql_quote "${current_commit}") AND \`${column}\` IS NULL" >/dev/null || true
    done
}

resolve_distribution_dir() {
    local candidate=""
    local -a candidates=(
        "${IOTDB_PATH}"/distribution/target/timechodb-*-SNAPSHOT-bin/timechodb-*-SNAPSHOT-bin
    )

    for candidate in "${candidates[@]}"; do
        if [ -d "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

publish_distribution() {
    local source_dir=""
    local target_dir="${REPO_PATH}/${commit_id}/apache-iotdb"
    local properties_file="${target_dir}/conf/iotdb-system.properties"

    source_dir="$(resolve_distribution_dir)" || die "missing compiled IoTDB distribution under ${IOTDB_PATH}/distribution/target"

    case "${REPO_PATH}" in
        ""|"/"|"/nasdata"|"/nasdata/repository")
            die "unsafe REPO_PATH: ${REPO_PATH}"
            ;;
    esac

    rm -rf -- "${REPO_PATH:?}/${commit_id}"
    mkdir -p "${target_dir}"
    cp -rf "${source_dir}/." "${target_dir}/"

    if [ -f "${properties_file}" ]; then
        printf '%s\n' "enforce_strong_password=false" >> "${properties_file}"
    fi
}

compile_current_commit() {
    local mvn_status=0

    date_time="$(date +%Y%m%d%H%M%S)"
    comp_mvn="$(mvn ${COMPILE_MVN_ARGS} 2>&1)"
    mvn_status=$?
    return "${mvn_status}"
}

load_commit_metadata() {
    commit_id="$(shorten_commit_id "$(git log --pretty=format:%H -1)")"
    commit_headline="$(git log --pretty=format:%s -1 | tr -d '"' | tr -d "'")"
    author="$(git log --pretty=format:%an -1)"
    commit_date_time="$(git log --pretty=format:%ai -1 | cut -b 1-19 | sed s/-//g | sed s/://g | sed s/[[:space:]]//g)"
}

process_commit() {
    local target_commit="$1"

    if commit_exists "${target_commit}"; then
        log "commit ${target_commit} already exists"
        replan_existing_commit "${target_commit}"
        return 0
    fi

    cd "${IOTDB_PATH}" || die "failed to cd to ${IOTDB_PATH}"
    timeout 100s git reset --hard "${target_commit}" || die "failed to reset to ${target_commit}"
    load_commit_metadata

    log "commit ${commit_id} is new, start compile"
    if compile_current_commit; then
        log "commit ${commit_id} compile success"
        publish_distribution
        if insert_commit_record ""; then
            PRECISE_TEST_REPO_PATH="${IOTDB_PATH}" apply_precise_test_plan "${commit_id}" "${commit_date_time}" "${author}"
            log "commit ${commit_id} test task plan published"
        else
            log "commit_history insert failed, skip precise test plan for ${commit_id}"
        fi
    else
        log "commit ${commit_id} compile failed"
        printf '%s\n' "${comp_mvn}" >> "${INIT_PATH}/compile-error.log"
        if ! insert_commit_record "CError"; then
            log "commit_history insert failed for compile error ${commit_id}"
        fi
        sendEmail 2
    fi
}

process_recent_commits() {
    local raw_commit=""
    local target_commit=""
    local -a commit_id_list=()

    mapfile -t commit_id_list < <(git log --pretty=format:%H -n "${COMPILE_COMMIT_WINDOW}" | cut -c1-"${COMPILE_COMMIT_ID_LENGTH}")
    for raw_commit in "${commit_id_list[@]}"; do
        target_commit="$(trim "${raw_commit}")"
        [ -n "${target_commit}" ] || continue
        process_commit "${target_commit}"
    done

    log "checked recent ${COMPILE_COMMIT_WINDOW} commits"
}

refresh_benchmark_repo_if_needed() {
    local day_of_week=""
    local hour=""
    local bm_repos_path=""

    day_of_week="$(date +%u)"
    hour="$(date +%H)"
    log "day_of_week=${day_of_week}, hour=${hour}"

    if [ "${day_of_week}" -eq 1 ] && [ "${hour}" -eq 01 ]; then
        bm_repos_path="/nasdata/repository/iot-benchmark"
        rm -rf -- "${bm_repos_path}"
        cp -rf "${INIT_PATH}/iot-benchmark" "${bm_repos_path}"
    fi
}

cleanup_old_runtime_records() {
    log "cleanup test runtime records older than 15 days"
    find /nasdata/repository/*/*/ -mtime +15 -type d -name "*" -exec rm -rf {} \;
}

main() {
    check_password
    ensure_dependencies
    trap restore_test_type_file EXIT
    mark_test_in_progress
    sync_source_repo
    process_recent_commits
    sync_source_repo
    refresh_benchmark_repo_if_needed
    cleanup_old_runtime_records
    sleep 300s
    restore_test_type_file
}

main "$@"
