#!/usr/bin/env bash
set -eu
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ATMOS_PATH="${ROOT}"
source "${ROOT}/script/modules/scenarios/windows_test.sh"

[ "${TEST_TYPE}" = windows_test ]
[ "${#QUERY_LIST[@]}" -eq 26 ]
[ "${#QUERY_LIST[@]}" -eq "${#QUERY_LABELS[@]}" ]
for config in "${INSERT_CONFIGS[@]}" "${QUERY_LIST[@]}"; do
    config_path="$(resolve_config_source "${config}")"
    grep -qx 'HOST=127.0.0.1' "${config_path}"
    if grep -Eq '^(HOST|ANOTHER_HOST)=.*172\.20\.' "${config_path}"; then
        exit 1
    fi
done

# Exercise a complete protocol case without starting processes or touching data.
declare -a observed_inserts=() observed_queries=() observed_backups=()
cleanup_processes() { :; }
set_env() { :; }
modify_iotdb_config() { :; }
set_protocol_class() { [ "$1" = 223 ]; }
start_iotdb() { :; }
stop_iotdb() { :; }
wait_for_iotdb_ready() { return 0; }
change_root_password() { :; }
sleep() { :; }
copy_windows_config() { observed_inserts+=("$1"); }
run_benchmark_case() { [ "$2" = INGESTION ]; }
run_query_case() {
    observed_queries+=("${data_type}:$1:$2")
    # A failed query must not suppress the rest of the query suite.
    [ "$1" != Q9-2 ]
}
backup_test_data() { observed_backups+=("$1"); }
TEST_IOTDB_PATH="${ROOT}"
if test_operation 223; then
    echo 'Query failure was not propagated' >&2
    exit 1
fi
[ "${#observed_inserts[@]}" -eq 4 ]
[ "${#observed_queries[@]}" -eq 52 ]
[ "${#observed_backups[@]}" -eq 4 ]
[ "${observed_queries[24]}" = seq_w:Q9-3:RANGE_QUERY_DESC ]
[ "${observed_queries[51]}" = unseq_w:Q10:VALUE_RANGE_QUERY_DESC ]
for observed_query in "${observed_queries[@]}"; do
    [[ "${observed_query}" == seq_w:* || "${observed_query}" == unseq_w:* ]]
done

# Keep SQL compatible with the original windows_test result table.
mysql_exec() { captured_sql="$1"; }
commit_date_time=20261010120000
test_date_time=20261010120000
commit_id=test
author=test
insert_result_row
[[ "${captured_sql}" == *'test_result_windows_test'* ]]
[[ "${captured_sql}" != *'query_suite_type'* ]]
[[ "${captured_sql}" != *'avgCPULoad'* ]]
printf 'windows_test tests passed\n'
