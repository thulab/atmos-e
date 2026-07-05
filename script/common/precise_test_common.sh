#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "precise_test_common.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "precise_test_common.sh requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi

if ! declare -p PRECISE_TEST_STATUS_COLUMNS >/dev/null 2>&1; then
    PRECISE_TEST_STATUS_COLUMNS=(
        se_insert
        unse_insert
        se_query
        unse_query
        compaction
        sql_coverage
        weeklytest_insert
        weeklytest_query
        api_insert
        api_insert_cts
        ts_performance
        cluster_insert
        cluster_insert_2
        cluster_insert_dt
        routine_test
        config_insert
        pipe_test
        pipe_test_win
        windows_test
        benchants
        helishi_test
        longrun_test
        delete_test
        treeview_query
        native_api_test
    )
fi

PRECISE_SELECTED_TESTS=()
PRECISE_SKIPPED_TESTS=()
PRECISE_MATCHED_RULES=()
PRECISE_FALLBACK_REASON=""

precise_log() {
    if declare -F log >/dev/null 2>&1; then
        log "$*"
    else
        printf '[%s] %s\n' "$(date '+%F %T')" "$*"
    fi
}

precise_trim() {
    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

precise_sql_quote() {
    local value="${1:-}"

    value="${value//\\/\\\\}"
    value="$(printf '%s' "${value}" | sed "s/'/''/g")"
    printf "'%s'" "${value}"
}

precise_mysql_exec() {
    local sql="$1"

    MYSQL_PWD="${PASSWORD}" mysql -N -B -h"${MYSQLHOSTNAME}" -P"${PORT}" -u"${USERNAME}" "${DBNAME}" -e "${sql}"
}

precise_rules_file() {
    local atmos_root="${ATMOS_PATH:-}"

    if [ -n "${PRECISE_TEST_RULES_FILE:-}" ]; then
        printf '%s\n' "${PRECISE_TEST_RULES_FILE}"
        return 0
    fi

    if [ -z "${atmos_root}" ]; then
        atmos_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    fi
    printf '%s\n' "${atmos_root}/conf/precise_test_rules.conf"
}

precise_is_known_test() {
    local test_name="$1"
    local known_test=""

    for known_test in "${PRECISE_TEST_STATUS_COLUMNS[@]}"; do
        if [ "${known_test}" = "${test_name}" ]; then
            return 0
        fi
    done
    return 1
}

precise_array_contains() {
    local wanted="$1"
    shift
    local current=""

    for current in "$@"; do
        if [ "${current}" = "${wanted}" ]; then
            return 0
        fi
    done
    return 1
}

precise_add_selected_test() {
    local test_name="$1"

    [ -n "${test_name}" ] || return 0
    precise_is_known_test "${test_name}" || return 0
    if [ "${#PRECISE_SELECTED_TESTS[@]}" -gt 0 ]; then
        precise_array_contains "${test_name}" "${PRECISE_SELECTED_TESTS[@]}" && return 0
    fi
    PRECISE_SELECTED_TESTS+=("${test_name}")
}

precise_add_all_tests() {
    local test_name=""

    for test_name in "${PRECISE_TEST_STATUS_COLUMNS[@]}"; do
        precise_add_selected_test "${test_name}"
    done
}

precise_add_test_list() {
    local test_list="$1"
    local item=""
    local -a tests=()

    test_list="$(precise_trim "${test_list}")"
    case "${test_list}" in
        ""|"NONE")
            return 0
            ;;
        "ALL")
            precise_add_all_tests
            return 0
            ;;
    esac

    IFS=',' read -r -a tests <<< "${test_list}"
    [ "${#tests[@]}" -gt 0 ] || return 0
    for item in "${tests[@]}"; do
        item="$(precise_trim "${item}")"
        precise_add_selected_test "${item}"
    done
}

precise_add_matched_rule() {
    local rule_id="$1"

    [ -n "${rule_id}" ] || return 0
    if [ "${#PRECISE_MATCHED_RULES[@]}" -gt 0 ]; then
        precise_array_contains "${rule_id}" "${PRECISE_MATCHED_RULES[@]}" && return 0
    fi
    PRECISE_MATCHED_RULES+=("${rule_id}")
}

precise_join_array() {
    local delimiter="$1"
    shift
    local first=1
    local item=""

    for item in "$@"; do
        if [ "${first}" -eq 1 ]; then
            printf '%s' "${item}"
            first=0
        else
            printf '%s%s' "${delimiter}" "${item}"
        fi
    done
}

precise_resolve_repo_path() {
    local candidate=""
    local -a candidates=()

    candidates+=("${PRECISE_TEST_REPO_PATH:-}")
    candidates+=("${IOTDB_GIT_PATH:-}")
    candidates+=("${IOTDB_SOURCE_PATH:-}")
    candidates+=("${IOTDB_PATH:-}")
    candidates+=("${INIT_PATH:-}/timechodb")
    candidates+=("${INIT_PATH:-}/apache-iotdb")
    candidates+=("/nasdata/repository/apache-iotdb")
    candidates+=("/nasdata/repository/iotdb")

    for candidate in "${candidates[@]}"; do
        [ -n "${candidate}" ] || continue
        if [ -d "${candidate}/.git" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

precise_emit_changed_files() {
    local commit_ref="$1"
    local repo_path="$2"
    local resolved_commit=""

    resolved_commit="$(git -C "${repo_path}" rev-parse --verify "${commit_ref}^{commit}" 2>/dev/null)" || return 1
    git -C "${repo_path}" diff-tree --root --no-commit-id --name-only -r -m "${resolved_commit}" | sort -u
}

precise_reset_plan() {
    PRECISE_SELECTED_TESTS=()
    PRECISE_SKIPPED_TESTS=()
    PRECISE_MATCHED_RULES=()
    PRECISE_FALLBACK_REASON=""
}

precise_select_tests_from_files() {
    local changed_files="$1"
    local rules_file=""
    local file_path=""
    local rule_id=""
    local path_regex=""
    local test_list=""
    local reason=""
    local matched_file=0
    local unmatched_file_count=0
    local changed_file_count=0

    rules_file="$(precise_rules_file)"
    if [ ! -f "${rules_file}" ]; then
        PRECISE_FALLBACK_REASON="missing_rules_file"
        precise_add_all_tests
        return 0
    fi

    while IFS= read -r file_path; do
        [ -n "${file_path}" ] || continue
        changed_file_count=$((changed_file_count + 1))
        matched_file=0

        while read -r rule_id path_regex test_list reason _; do
            [ -n "${rule_id}" ] || continue
            case "${rule_id}" in
                \#*) continue ;;
            esac
            [ -n "${path_regex}" ] || continue
            if [[ "${file_path}" =~ ${path_regex} ]]; then
                matched_file=1
                precise_add_matched_rule "${rule_id}"
                precise_add_test_list "${test_list}"
                if [ "$(precise_trim "${test_list}")" = "NONE" ]; then
                    break
                fi
            fi
        done < "${rules_file}"

        if [ "${matched_file}" -eq 0 ]; then
            unmatched_file_count=$((unmatched_file_count + 1))
        fi
    done <<< "${changed_files}"

    if [ "${changed_file_count}" -eq 0 ]; then
        PRECISE_FALLBACK_REASON="no_changed_files"
        precise_add_all_tests
        return 0
    fi

    if [ "${unmatched_file_count}" -gt 0 ]; then
        PRECISE_FALLBACK_REASON="unmatched_files:${unmatched_file_count}"
        precise_add_all_tests
    fi
}

precise_build_skipped_tests() {
    local test_name=""

    PRECISE_SKIPPED_TESTS=()
    for test_name in "${PRECISE_TEST_STATUS_COLUMNS[@]}"; do
        if [ "${#PRECISE_SELECTED_TESTS[@]}" -eq 0 ] || ! precise_array_contains "${test_name}" "${PRECISE_SELECTED_TESTS[@]}"; then
            PRECISE_SKIPPED_TESTS+=("${test_name}")
        fi
    done
}

precise_table_exists() {
    local table_name="$1"
    local count=""

    count="$(precise_mysql_exec "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = $(precise_sql_quote "${table_name}")" 2>/dev/null || true)"
    [ "${count}" = "1" ]
}

precise_column_exists() {
    local table_name="$1"
    local column_name="$2"
    local count=""

    count="$(precise_mysql_exec "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = $(precise_sql_quote "${table_name}") AND column_name = $(precise_sql_quote "${column_name}")" 2>/dev/null || true)"
    [ "${count}" = "1" ]
}

precise_update_skipped_statuses() {
    local commit_ref="$1"
    local table_name="${TABLENAME:-commit_history}"
    local test_name=""
    local update_sql=""

    [ "${#PRECISE_SKIPPED_TESTS[@]}" -gt 0 ] || return 0
    for test_name in "${PRECISE_SKIPPED_TESTS[@]}"; do
        [[ "${test_name}" =~ ^[A-Za-z0-9_]+$ ]] || continue
        precise_column_exists "${table_name}" "${test_name}" || continue
        update_sql="UPDATE ${table_name} SET \`${test_name}\` = 'skip' WHERE commit_id = $(precise_sql_quote "${commit_ref}") AND \`${test_name}\` IS NULL"
        precise_mysql_exec "${update_sql}" >/dev/null 2>&1 || precise_log "precise test: failed to mark ${test_name}=skip for ${commit_ref}"
    done
}

precise_record_impact() {
    local commit_ref="$1"
    local commit_time="$2"
    local commit_author="$3"
    local changed_files="$4"
    local selected_tests="$5"
    local skipped_tests="$6"
    local matched_rules="$7"
    local fallback_reason="$8"
    local changed_file_count=0
    local sql=""

    precise_table_exists "commit_test_impact" || return 0
    if ! [[ "${commit_time}" =~ ^[0-9]+$ ]]; then
        commit_time=0
    fi

    if [ -n "${changed_files}" ]; then
        while IFS= read -r _; do
            changed_file_count=$((changed_file_count + 1))
        done <<< "${changed_files}"
    fi

    sql="INSERT INTO commit_test_impact (
        commit_id, commit_date_time, author, changed_file_count, changed_files,
        matched_rules, selected_tests, skipped_tests, fallback_reason
    ) VALUES (
        $(precise_sql_quote "${commit_ref}"),
        ${commit_time:-0},
        $(precise_sql_quote "${commit_author}"),
        ${changed_file_count},
        $(precise_sql_quote "${changed_files}"),
        $(precise_sql_quote "${matched_rules}"),
        $(precise_sql_quote "${selected_tests}"),
        $(precise_sql_quote "${skipped_tests}"),
        $(precise_sql_quote "${fallback_reason}")
    ) ON DUPLICATE KEY UPDATE
        commit_date_time = VALUES(commit_date_time),
        author = VALUES(author),
        changed_file_count = VALUES(changed_file_count),
        changed_files = VALUES(changed_files),
        matched_rules = VALUES(matched_rules),
        selected_tests = VALUES(selected_tests),
        skipped_tests = VALUES(skipped_tests),
        fallback_reason = VALUES(fallback_reason),
        created_at = CURRENT_TIMESTAMP"

    precise_mysql_exec "${sql}" >/dev/null 2>&1 || precise_log "precise test: failed to record impact for ${commit_ref}"
}

apply_precise_test_plan() {
    local commit_ref="$1"
    local commit_time="${2:-0}"
    local commit_author="${3:-}"
    local repo_path=""
    local changed_files=""
    local selected_tests=""
    local skipped_tests=""
    local matched_rules=""

    if [ "${PRECISE_TEST_ENABLED:-1}" = "0" ]; then
        precise_log "precise test disabled, keep full task set for ${commit_ref}"
        return 0
    fi

    precise_reset_plan

    if repo_path="$(precise_resolve_repo_path 2>/dev/null)" && changed_files="$(precise_emit_changed_files "${commit_ref}" "${repo_path}" 2>/dev/null)"; then
        precise_select_tests_from_files "${changed_files}"
    else
        PRECISE_FALLBACK_REASON="missing_git_repo_or_commit"
        precise_add_all_tests
    fi

    precise_build_skipped_tests

    if [ "${#PRECISE_SELECTED_TESTS[@]}" -gt 0 ]; then
        selected_tests="$(precise_join_array "," "${PRECISE_SELECTED_TESTS[@]}")"
    fi
    if [ "${#PRECISE_SKIPPED_TESTS[@]}" -gt 0 ]; then
        skipped_tests="$(precise_join_array "," "${PRECISE_SKIPPED_TESTS[@]}")"
    fi
    if [ "${#PRECISE_MATCHED_RULES[@]}" -gt 0 ]; then
        matched_rules="$(precise_join_array "," "${PRECISE_MATCHED_RULES[@]}")"
    fi

    precise_update_skipped_statuses "${commit_ref}"
    precise_record_impact "${commit_ref}" "${commit_time}" "${commit_author}" "${changed_files}" "${selected_tests}" "${skipped_tests}" "${matched_rules}" "${PRECISE_FALLBACK_REASON}"

    precise_log "precise test plan ${commit_ref}: selected=[${selected_tests:-none}], skipped=[${skipped_tests:-none}], reason=[${PRECISE_FALLBACK_REASON:-rules}]"
    return 0
}
