#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "benchmark_result_common.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "benchmark_result_common.sh requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi

read_benchmark_csv_operation_result() {
    local csv_file="$1"
    local operation_label="$2"
    local throughput_line=""
    local latency_line=""

    [ -f "${csv_file}" ] || return 1

    throughput_line="$(
        awk -F, -v operation_label="${operation_label}" '
            function trim_field(value) {
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                return value
            }
            trim_field($1) == operation_label {
                for (i = 2; i <= 6; i++) {
                    value = trim_field($i)
                    printf "%s%s", value, (i == 6 ? ORS : OFS)
                }
                exit
            }
        ' OFS=$'\t' "${csv_file}"
    )"

    latency_line="$(
        awk -F, -v operation_label="${operation_label}" '
            function trim_field(value) {
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                return value
            }
            trim_field($1) == operation_label {
                count++
                if (count == 2) {
                    for (i = 2; i <= 12; i++) {
                        value = trim_field($i)
                        printf "%s%s", value, (i == 12 ? ORS : OFS)
                    }
                    exit
                }
            }
        ' OFS=$'\t' "${csv_file}"
    )"

    [ -n "${throughput_line}" ] || return 1
    [ -n "${latency_line}" ] || return 1

    printf '%s\t%s\n' "${throughput_line}" "${latency_line}"
}

parse_benchmark_csv_operation_result() {
    local csv_file="$1"
    local operation_label="$2"
    local result_line=""

    result_line="$(read_benchmark_csv_operation_result "${csv_file}" "${operation_label}")" || return 1
    IFS=$'\t' read -r \
        okOperation okPoint failOperation failPoint throughput \
        Latency MIN P10 P25 MEDIAN P75 P90 P95 P99 P999 MAX <<< "${result_line}"
}

parse_ingestion_result() {
    local csv_file="$1"

    parse_benchmark_csv_operation_result "${csv_file}" "INGESTION"
}

parse_query_result() {
    local csv_file="$1"
    local query_label="$2"

    parse_benchmark_csv_operation_result "${csv_file}" "${query_label}"
}
