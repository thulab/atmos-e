#!/usr/bin/env bash
# 场景名称：TSFile 文件格式性能测试
# 测试目的：通过 TSFBench 文件类负载评估 TsFile 在树模型和表模型配置下的性能。
# 具体步骤：
# 步骤一：准备 TSFile 候选版本、TSFBench 及 Python 构建环境。
# 步骤二：根据用例配置准备并校验候选后端。
# 步骤三：运行 TSFBench 文件类工作负载并生成结果 CSV。
# 步骤四：解析 CSV 结果并记录失败阶段信息。
# 步骤五：将测试结果持久化到数据库。

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
if shopt -oq posix; then
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

set -u
set -o pipefail

readonly TEST_TYPE="tsfbench_tsfile"
readonly SCENARIO_ID="tsfbench_tsfile"
readonly TASK_TEST_TYPE="tsfbench_tsfile"
readonly SCENARIO_FAILURE_POLICY="continue_and_fail"
readonly RESULT_TABLE_NAME="test_result_${TEST_TYPE}"

readonly -a SCENARIO_CASES=(
    $'case=series_case01_table_lz4\tenv=series_case01_table_lz4.env'
    $'case=series_case01_table_gzip\tenv=series_case01_table_gzip.env'
    $'case=series_profile_compare\tenv=series_profile_compare.env'
    $'case=series_micro_decode\tenv=series_micro_decode.env'
    $'case=grid_flatten_compare\tenv=grid_flatten_compare.env'
    $'case=point_sparse_compare\tenv=point_sparse_compare.env'
)

: "${INIT_PATH:=/root/zk_test}"
: "${ATMOS_PATH:=${INIT_PATH}/atmos-e}"
: "${BM_PATH:=${INIT_PATH}/iot-benchmark}"
: "${REPOS_PATH:=/nasdata/repository/master}"
: "${BM_REPOS_PATH:=/nasdata/repository/iot-benchmark}"
: "${TEST_INIT_PATH:=/data/qa}"
: "${TEST_IOTDB_PATH:=${TEST_INIT_PATH}/apache-iotdb}"
: "${MYSQLHOSTNAME:=${MYSQL_HOST:-111.200.37.158}}"
: "${PORT:=${MYSQL_PORT:-13306}}"
: "${USERNAME:=${MYSQL_USERNAME:-iotdbatm}}"
: "${PASSWORD:=${MYSQL_PASSWORD:-${ATMOS_DB_PASSWORD:-}}}"
: "${DBNAME:=QA_ATM}"
METRIC_SERVER="${METRIC_SERVER:-111.200.37.158:19090}"
readonly METRIC_SERVER

readonly TSFBENCH_CONF_DIR="${ATMOS_PATH}/conf/${TEST_TYPE}"
readonly TSFBENCH_CASE_DIR="${TSFBENCH_CONF_DIR}/cases"
readonly TSFBENCH_QUERY_DIR="${TSFBENCH_CONF_DIR}/queries"
readonly TSFBENCH_DEFAULT_REPOS_PATH="${INIT_PATH}/TSFBenchmark"
readonly TSFBENCH_DEFAULT_RESULT_ROOT="${TEST_INIT_PATH}/${TEST_TYPE}/results"
readonly TSFBENCH_GLOBAL_PREPARE_BACKENDS="${TSFBENCH_PREPARE_BACKENDS:-0}"
readonly TSFBENCH_GLOBAL_REQUIRE_PREPARED="${TSFBENCH_REQUIRE_PREPARED:-1}"
readonly TSFBENCH_GLOBAL_PREPARE_TIMEOUT_SECONDS="${TSFBENCH_PREPARE_TIMEOUT_SECONDS:-3600}"
readonly TSFBENCH_GLOBAL_RESULT_ROOT="${TSFBENCH_RESULT_ROOT:-${TSFBENCH_DEFAULT_RESULT_ROOT}}"
readonly TSFBENCH_GLOBAL_HOME_BASE_DIR="${TSFBENCH_HOME_BASE_DIR:-${TSFBENCH_HOME_DIR:-${TSFBENCH_HOME:-${TEST_INIT_PATH}/${TEST_TYPE}/home}}}"
readonly TSFBENCH_GLOBAL_REPOS_PATH="${TSFBENCH_REPOS_PATH:-${TSFBENCH_DEFAULT_REPOS_PATH}}"
readonly TSFBENCH_GLOBAL_BIN="${TSFBENCH_BIN:-}"
readonly TSFILE_REPOS_PATH="${TSFILE_REPOS_PATH:-${TSFILE_PATH:-${INIT_PATH}/tsfile}}"
readonly TSFILE_BRANCH="${TSFILE_BRANCH:-develop}"
readonly TSFILE_SYNC_TIMEOUT_SECONDS="${TSFILE_SYNC_TIMEOUT_SECONDS:-300}"
readonly TSFILE_BUILD_TIMEOUT_SECONDS="${TSFILE_BUILD_TIMEOUT_SECONDS:-7200}"
readonly TSFILE_PREPARE_TIMEOUT_SECONDS="${TSFILE_PREPARE_TIMEOUT_SECONDS:-3600}"
readonly TSFILE_BUILD_PYTHON_WHEEL="${TSFILE_BUILD_PYTHON_WHEEL:-1}"
readonly TSFILE_PREPARE_CANDIDATE_WHEEL="${TSFILE_PREPARE_CANDIDATE_WHEEL:-1}"
readonly TSFILE_TABLE_BACKEND_SELECTOR="${TSFILE_TABLE_BACKEND_SELECTOR:-tsfile@candidate+table}"
readonly TSFILE_TREE_BACKEND_SELECTOR="${TSFILE_TREE_BACKEND_SELECTOR:-tsfile@candidate+tree}"
readonly TSFILE_CANDIDATE_BACKENDS="${TSFILE_CANDIDATE_BACKENDS:-${TSFILE_TABLE_BACKEND_SELECTOR} ${TSFILE_TREE_BACKEND_SELECTOR}}"
readonly TSFILE_FORCE_TEST="${TSFILE_FORCE_TEST:-0}"
readonly TSFILE_NO_UPDATE_SLEEP_SECONDS="${TSFILE_NO_UPDATE_SLEEP_SECONDS:-60}"
readonly TSFILE_COMMIT_LENGTH="${TSFILE_COMMIT_LENGTH:-12}"
readonly TSFBENCH_HOME_PER_COMMIT="${TSFBENCH_HOME_PER_COMMIT:-1}"

TSFBENCH_GLOBAL_HOME_DIR="${TSFBENCH_GLOBAL_HOME_BASE_DIR}"
TSFBENCH_RESULT_ROOT="${TSFBENCH_GLOBAL_RESULT_ROOT}"
TSFBENCH_HOME_DIR="${TSFBENCH_GLOBAL_HOME_DIR}"
TSFBENCH_REPOS_PATH="${TSFBENCH_GLOBAL_REPOS_PATH}"
TSFBENCH_BIN="${TSFBENCH_GLOBAL_BIN}"

commit_id=""
author=""
commit_date_time=""
test_date_time=""
last_tsfile_commit=""
current_tsfile_wheel=""
current_tsfile_version=""
tsfile_table_backend_selector="${TSFILE_TABLE_BACKEND_SELECTOR}"
tsfile_tree_backend_selector="${TSFILE_TREE_BACKEND_SELECTOR}"
tsfile_candidate_backends="${TSFILE_CANDIDATE_BACKENDS}"
tsfile_prepare_root=""

tsfbench_command_cwd=""
declare -a tsfbench_command=()

case_id=""
case_env_file=""
case_start_time=""
case_end_time=""
case_cost_time=0
case_status="running"
case_exit_code=0
case_result_csv=""
case_manifest_json=""
case_workdir=""
case_log_file=""
case_command_line=""
case_remark=""

# 输出带时间戳的 TSFile 场景日志。
log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

# 输出错误信息并终止场景脚本。
die() {
    log "ERROR: $*"
    exit 1
}

# 检查单个外部命令是否可用。
require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# 逐项校验场景运行所需的外部命令。
require_commands() {
    local cmd=""

    for cmd in "$@"; do
        require_command "${cmd}"
    done
}

# 移除输入字符串首尾空白字符。
trim() {
    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

# 输出当前本地日期时间。
current_datetime() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 将日期时间转换为 Unix 秒级时间戳。
datetime_to_epoch() {
    date -d "$1" +%s
}

# 转义 SQL 字符串并添加单引号。
sql_quote() {
    local value="${1:-}"

    value="${value//\\/\\\\}"
    value="$(printf '%s' "${value}" | sed "s/'/''/g")"
    printf "'%s'" "${value}"
}

# 使用配置的数据库连接执行 SQL 语句。
mysql_exec() {
    local sql="$1"
    local mysql_port="${MYSQL_PORT:-${PORT:-}}"
    local mysql_username="${MYSQL_USERNAME:-${USERNAME:-}}"
    local mysql_password="${MYSQL_PASSWORD:-${PASSWORD:-}}"

    MYSQL_PWD="${mysql_password}" mysql -N -B \
        -h"${MYSQLHOSTNAME}" -P"${mysql_port}" -u"${mysql_username}" \
        "${DBNAME}" -e "${sql}"
}

# 检查数据库连接密码是否已配置。
check_password() {
    local mysql_password="${MYSQL_PASSWORD:-${PASSWORD:-}}"

    [ -n "${mysql_password}" ] || die "MYSQL_PASSWORD or ATMOS_DB_PASSWORD is not set"
}

# 将测试类型写入调度器状态文件。
write_test_type_file() {
    local value="$1"

    [ -n "${value}" ] || {
        log "cannot write empty test type"
        return 1
    }
    mkdir -p "${INIT_PATH}"
    printf '%s\n' "${value}" > "${INIT_PATH}/test_type_file"
}

# 将调度器状态设置为测试执行中。
mark_test_in_progress() {
    write_test_type_file "ontesting"
}

# 将调度器状态恢复为当前场景类型。
restore_test_type_file() {
    local current_test_type="${1:-${TEST_TYPE:-${test_type:-}}}"

    write_test_type_file "${current_test_type}"
}

# 在指定仓库工作树中执行 Git 命令。
git_repo_exec() {
    local repository="$1"
    shift

    [ -d "${repository}/.git" ] || die "invalid git repository: ${repository}"
    git --git-dir="${repository}/.git" --work-tree="${repository}" "$@"
}

# 读取仓库当前提交哈希并按配置截短。
git_current_commit() {
    local repository="$1"

    if [ -n "${TSFILE_COMMIT_LENGTH}" ]; then
        git_repo_exec "${repository}" rev-parse --short="${TSFILE_COMMIT_LENGTH}" HEAD
    else
        git_repo_exec "${repository}" rev-parse HEAD
    fi
}

# 读取仓库当前提交的作者名称。
git_current_author() {
    local repository="$1"

    git_repo_exec "${repository}" show -s --format=%an HEAD
}

# 读取仓库当前提交的 Unix 时间戳。
git_current_epoch() {
    local repository="$1"

    git_repo_exec "${repository}" show -s --format=%ct HEAD
}

# 拉取并快进同步 TSFile 指定分支。
sync_tsfile_repository() {
    local repository="${TSFILE_REPOS_PATH}"
    local branch="${TSFILE_BRANCH}"

    [ -d "${repository}/.git" ] || die "missing TSFile git repository: ${repository}"
    log "sync TSFile repository=${repository} branch=${branch}"
    timeout "${TSFILE_SYNC_TIMEOUT_SECONDS}s" \
        git --git-dir="${repository}/.git" --work-tree="${repository}" fetch origin "${branch}" || return 1

    if git_repo_exec "${repository}" show-ref --verify --quiet "refs/heads/${branch}"; then
        git_repo_exec "${repository}" checkout "${branch}" || return 1
    else
        git_repo_exec "${repository}" checkout --track "origin/${branch}" || return 1
    fi

    log "stash local TSFile changes before sync to avoid pull/rebase conflicts"
    timeout "${TSFILE_SYNC_TIMEOUT_SECONDS}s" \
        git --git-dir="${repository}/.git" --work-tree="${repository}" stash push -u -m "atmos-e auto-stash before sync" >/dev/null 2>&1 || true

    timeout "${TSFILE_SYNC_TIMEOUT_SECONDS}s" \
        git --git-dir="${repository}/.git" --work-tree="${repository}" pull --ff-only origin "${branch}"
}

# 加载当前 TSFile 提交的标识、作者和时间信息。
load_current_tsfile_commit_info() {
    local epoch=""

    commit_id="$(git_current_commit "${TSFILE_REPOS_PATH}")"
    author="$(git_current_author "${TSFILE_REPOS_PATH}")"
    epoch="$(git_current_epoch "${TSFILE_REPOS_PATH}")"
    commit_date_time="$(date -d "@${epoch}" +%Y%m%d%H%M%S)"
}

# 判断当前 TSFile 提交是否需要执行测试。
should_run_current_tsfile_commit() {
    local force_test="$1"

    if bool_enabled "${force_test}"; then
        return 0
    fi
    [ "${last_tsfile_commit}" != "${commit_id}" ]
}

# 同步并认领新的 TSFile 提交用于本轮测试。
claim_current_tsfile_commit() {
    local force_test="$1"

    last_tsfile_commit="$(git_current_commit "${TSFILE_REPOS_PATH}")"
    sync_tsfile_repository || return $?
    load_current_tsfile_commit_info

    if ! should_run_current_tsfile_commit "${force_test}"; then
        log "no TSFile repository update for ${TEST_TYPE}: commit=${commit_id}"
        return 10
    fi

    test_date_time="$(date +%Y%m%d%H%M%S)"
    log "claim TSFile commit=${commit_id}, author=${author}, commit_date_time=${commit_date_time}, previous_commit=${last_tsfile_commit}"
}

# 按提交标识设置隔离的 TSFBench 工作目录。
set_commit_scoped_tsfbench_home() {
    if bool_enabled "${TSFBENCH_HOME_PER_COMMIT}"; then
        TSFBENCH_GLOBAL_HOME_DIR="${TSFBENCH_GLOBAL_HOME_BASE_DIR}/${commit_id}"
    else
        TSFBENCH_GLOBAL_HOME_DIR="${TSFBENCH_GLOBAL_HOME_BASE_DIR}"
    fi
    export TSFBENCH_HOME="${TSFBENCH_GLOBAL_HOME_DIR}"
}

# 将每个用例配置重置为场景级默认值。
reset_case_config() {
    TSFBENCH_CASE_ID=""
    TSFBENCH_TITLE=""
    TSFBENCH_MODALITY="series_1d"
    TSFBENCH_SUITE=""
    TSFBENCH_BACKENDS=""
    TSFBENCH_REFERENCE="csv"
    TSFBENCH_CODECS=""
    TSFBENCH_DEVICES=""
    TSFBENCH_SENSORS=""
    TSFBENCH_TIMES=""
    TSFBENCH_NY=""
    TSFBENCH_NX=""
    TSFBENCH_STATIONS=""
    TSFBENCH_DENSITY=""
    TSFBENCH_MISSING_RATE=""
    TSFBENCH_DISORDER=""
    TSFBENCH_SEED="666"
    TSFBENCH_REPEAT="5"
    TSFBENCH_WARMUP="1"
    TSFBENCH_CONCURRENCY="1"
    TSFBENCH_QUERY_FILE=""
    TSFBENCH_MICRO="0"
    TSFBENCH_KEEP_ARTIFACTS="1"
    TSFBENCH_TIMEOUT_SECONDS="21600"
    TSFBENCH_PREPARE_BACKENDS="${TSFBENCH_GLOBAL_PREPARE_BACKENDS}"
    TSFBENCH_REQUIRE_PREPARED="${TSFBENCH_GLOBAL_REQUIRE_PREPARED}"
    TSFBENCH_PREPARE_TIMEOUT_SECONDS="${TSFBENCH_GLOBAL_PREPARE_TIMEOUT_SECONDS}"
    TSFBENCH_RESULT_ROOT="${TSFBENCH_GLOBAL_RESULT_ROOT}"
    TSFBENCH_HOME_DIR="${TSFBENCH_GLOBAL_HOME_DIR}"
    TSFBENCH_REPOS_PATH="${TSFBENCH_GLOBAL_REPOS_PATH}"
    TSFBENCH_BIN="${TSFBENCH_GLOBAL_BIN}"
    TSFBENCH_IOT_DATA_PATH=""
    TSFBENCH_IOT_TIMESTAMP_UNIT=""
    TSFBENCH_IOT_MAX_CELLS=""
    TSFBENCH_REAL=""
    TSFBENCH_GHCN_ELEMENT=""
    TSFBENCH_GHCN_YEAR_START=""
    TSFBENCH_GHCN_YEAR_END=""
}

# 校验 TSFile 和 TSFBench 场景所需依赖。
ensure_runtime_dependencies() {
    require_commands awk date git grep mkdir mysql sed sleep timeout tr
    if bool_enabled "${TSFILE_BUILD_PYTHON_WHEEL}"; then
        require_command mvn
    fi
}

# 输出当前场景声明的用例矩阵行。
scenario_cases_local() {
    printf '%s\n' "${SCENARIO_CASES[@]}"
}

# 从矩阵行中提取指定维度的值。
matrix_value() {
    local row="$1"
    local target="$2"
    local assignment=""
    local key=""
    local value=""
    local -a assignments=()

    IFS=$'\t' read -r -a assignments <<< "${row}"
    for assignment in "${assignments[@]}"; do
        key="${assignment%%=*}"
        value="${assignment#*=}"
        if [ "${key}" = "${target}" ]; then
            printf '%s\n' "${value}"
            return 0
        fi
    done
    return 1
}

# 将逗号或空格分隔的文本拆分到指定数组。
split_words() {
    local value="${1//,/ }"
    local -n out_ref="$2"

    # shellcheck disable=SC2206
    out_ref=(${value})
}

# 判断输入文本是否表示启用状态。
bool_enabled() {
    case "${1:-0}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

# 将任意文本转换为适合作为文件名的字符形式。
safe_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9_.=-' '_'
}

# 根据结果 CSV 路径生成关联清单文件路径。
manifest_path_for_csv() {
    local csv_file="$1"
    local base="${csv_file##*/}"
    local dir="${csv_file%/*}"

    printf '%s/%s.manifest.json\n' "${dir}" "${base%.*}"
}

# 将有限数值转换为 SQL 数值，否则返回 NULL。
sql_number_or_null() {
    local value="${1:-}"

    case "${value}" in
        ""|nan|NaN|NAN|inf|-inf|Infinity|-Infinity)
            printf 'NULL'
            return 0
            ;;
    esac
    if [[ "${value}" =~ ^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$ ]]; then
        printf '%s' "${value}"
    else
        printf 'NULL'
    fi
}

# 将整数转换为 SQL 整数，否则按数值或 NULL 处理。
sql_int_or_null() {
    local value="${1:-}"

    if [[ "${value}" =~ ^-?[0-9]+$ ]]; then
        printf '%s' "${value}"
    else
        sql_number_or_null "${value}"
    fi
}

# 将支持的日期格式转换为 SQL 日期时间值。
sql_datetime_or_null() {
    local value="${1:-}"
    local formatted=""

    if [ -z "${value}" ]; then
        printf 'NULL'
        return 0
    fi

    if [[ "${value}" =~ ^[0-9]{14}$ ]]; then
        formatted="${value:0:4}-${value:4:2}-${value:6:2} ${value:8:2}:${value:10:2}:${value:12:2}"
        sql_quote "${formatted}"
        return 0
    fi

    if [[ "${value}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]T][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        formatted="${value/T/ }"
        sql_quote "${formatted}"
        return 0
    fi

    printf 'NULL'
}

# 将布尔文本转换为 SQL 数值或 NULL。
sql_bool_or_null() {
    case "${1:-}" in
        true|True|TRUE|1) printf '1' ;;
        false|False|FALSE|0) printf '0' ;;
        *) printf 'NULL' ;;
    esac
}

# 将非空文本转义为 SQL 字符串，空值返回 NULL。
sql_text_or_null() {
    local value="${1:-}"

    if [ -n "${value}" ]; then
        sql_quote "${value}"
    else
        printf 'NULL'
    fi
}

# 将参数数组格式化为可读且可复现的命令行文本。
format_command_line() {
    local -a values=("$@")
    local rendered=""
    local item=""

    for item in "${values[@]}"; do
        printf -v rendered '%s%q ' "${rendered}" "${item}"
    done
    printf '%s' "${rendered% }"
}

# 按配置、PATH 或源码仓库解析 TSFBench 启动命令。
resolve_tsfbench_command() {
    tsfbench_command=()
    tsfbench_command_cwd=""

    if [ -n "${TSFBENCH_BIN:-}" ]; then
        tsfbench_command=("${TSFBENCH_BIN}")
        return 0
    fi

    if command -v tsfbench >/dev/null 2>&1; then
        tsfbench_command=(tsfbench)
        return 0
    fi

    if [ -d "${TSFBENCH_REPOS_PATH}" ]; then
        if command -v python3 >/dev/null 2>&1; then
            tsfbench_command=(python3 -m harness.cli)
        elif command -v python >/dev/null 2>&1; then
            tsfbench_command=(python -m harness.cli)
        else
            log "missing python for TSFBenchmark repository execution"
            return 42
        fi
        tsfbench_command_cwd="${TSFBENCH_REPOS_PATH}"
        return 0
    fi

    log "missing tsfbench command. Set TSFBENCH_BIN or TSFBENCH_REPOS_PATH"
    return 42
}

# 在超时限制和指定工作目录下运行 TSFBench 命令。
run_tsfbench() {
    local timeout_seconds="$1"
    local log_file="$2"
    shift 2
    local status=0

    mkdir -p "${log_file%/*}"
    (
        if [ -n "${tsfbench_command_cwd}" ]; then
            cd "${tsfbench_command_cwd}" || exit 127
        fi
        if [ -n "${TSFBENCH_HOME_DIR:-}" ]; then
            export TSFBENCH_HOME="${TSFBENCH_HOME_DIR}"
        fi
        timeout "${timeout_seconds}s" "${tsfbench_command[@]}" "$@"
    ) > "${log_file}" 2>&1
    status=$?
    return "${status}"
}

# 在候选目录中查找最新构建的 TSFile Python wheel。
find_latest_tsfile_wheel() {
    local dist_dir="${TSFILE_REPOS_PATH}/python/dist"
    local wheel=""
    local newest=""

    [ -d "${dist_dir}" ] || return 1
    shopt -s nullglob
    for wheel in "${dist_dir}"/*.whl; do
        if [ -z "${newest}" ] || [ "${wheel}" -nt "${newest}" ]; then
            newest="${wheel}"
        fi
    done
    shopt -u nullglob

    [ -n "${newest}" ] || return 1
    printf '%s\n' "${newest}"
}

# 从 wheel 文件名提取 TSFile 包版本。
extract_tsfile_wheel_version() {
    local wheel_path="$1"
    local wheel_name="${wheel_path##*/}"
    local remainder=""
    local version=""

    case "${wheel_name}" in
        tsfile-*.whl) ;;
        *)
            log "unexpected TSFile wheel name: ${wheel_name}"
            return 41
            ;;
    esac

    remainder="${wheel_name%.whl}"
    remainder="${remainder#tsfile-}"
    version="${remainder%%-*}"
    if [ -z "${version}" ] || [ "${version}" = "${remainder}" ]; then
        log "cannot parse TSFile wheel version from ${wheel_name}"
        return 41
    fi
    printf '%s\n' "${version}"
}

# 根据模型解析 TSFile 候选后端选择器。
resolve_tsfile_candidate_backend_selector() {
    local selector="$1"
    local profile=""

    case "${selector}" in
        tsfile@candidate+*)
            [ -n "${current_tsfile_version}" ] || {
                log "cannot resolve ${selector} without TSFile wheel version"
                return 41
            }
            profile="${selector#tsfile@candidate+}"
            printf 'tsfile@%s+%s\n' "${current_tsfile_version}" "${profile}"
            ;;
        tsfile@candidate)
            [ -n "${current_tsfile_version}" ] || {
                log "cannot resolve ${selector} without TSFile wheel version"
                return 41
            }
            printf 'tsfile@%s\n' "${current_tsfile_version}"
            ;;
        *)
            printf '%s\n' "${selector}"
            ;;
    esac
}

# 生成当前用例所需的 TSFile 候选后端列表。
resolve_tsfile_candidate_backend_list() {
    local selector_list="$1"
    local backend=""
    local resolved=""
    local rendered=""
    local -a backends=()

    split_words "${selector_list}" backends
    for backend in "${backends[@]}"; do
        resolved="$(resolve_tsfile_candidate_backend_selector "${backend}")" || return $?
        rendered="${rendered}${rendered:+ }${resolved}"
    done
    printf '%s\n' "${rendered}"
}

# 刷新候选后端选择器及模型对应关系。
refresh_tsfile_backend_selectors() {
    tsfile_table_backend_selector="$(resolve_tsfile_candidate_backend_selector "${TSFILE_TABLE_BACKEND_SELECTOR}")" || return $?
    tsfile_tree_backend_selector="$(resolve_tsfile_candidate_backend_selector "${TSFILE_TREE_BACKEND_SELECTOR}")" || return $?
    tsfile_candidate_backends="$(resolve_tsfile_candidate_backend_list "${TSFILE_CANDIDATE_BACKENDS}")" || return $?
}

# 编译并打包当前 TSFile 源码为 Python wheel。
build_tsfile_python_wheel() {
    local log_file="${tsfile_prepare_root}/tsfile-python-build.log"
    local status=0

    mkdir -p "${tsfile_prepare_root}"
    if bool_enabled "${TSFILE_BUILD_PYTHON_WHEEL}"; then
        log "build TSFile Python wheel from ${TSFILE_REPOS_PATH}"
        (
            cd "${TSFILE_REPOS_PATH}" || exit 127
            timeout "${TSFILE_BUILD_TIMEOUT_SECONDS}s" mvn clean install -P with-python -DskipTests
        ) > "${log_file}" 2>&1
        status=$?
        if [ "${status}" -ne 0 ]; then
            log "TSFile Python wheel build failed, log=${log_file}"
            return "${status}"
        fi
    else
        log "skip TSFile Python wheel build, use existing python/dist wheel"
    fi

    current_tsfile_wheel="$(find_latest_tsfile_wheel)" || {
        log "missing TSFile Python wheel under ${TSFILE_REPOS_PATH}/python/dist"
        return 41
    }
    current_tsfile_version="$(extract_tsfile_wheel_version "${current_tsfile_wheel}")" || return $?
    refresh_tsfile_backend_selectors || return $?
    log "use TSFile Python wheel: ${current_tsfile_wheel}, version=${current_tsfile_version}"
    log "use TSFBenchmark candidate backends: ${tsfile_candidate_backends}"
}

# 为 TSFBench 准备当前提交对应的候选后端。
prepare_candidate_tsfbench_backends() {
    local backend=""
    local log_file=""
    local status=0
    local -a candidate_backends=()

    bool_enabled "${TSFILE_PREPARE_CANDIDATE_WHEEL}" || {
        log "skip TSFBenchmark candidate backend prepare"
        return 0
    }

    [ -n "${current_tsfile_wheel}" ] || return 41
    TSFBENCH_HOME_DIR="${TSFBENCH_GLOBAL_HOME_DIR}"
    mkdir -p "${TSFBENCH_HOME_DIR}" "${tsfile_prepare_root}"
    resolve_tsfbench_command

    split_words "${tsfile_candidate_backends}" candidate_backends
    for backend in "${candidate_backends[@]}"; do
        log_file="${tsfile_prepare_root}/prepare.$(safe_name "${backend}").log"
        log "prepare TSFBenchmark backend=${backend}"
        run_tsfbench "${TSFILE_PREPARE_TIMEOUT_SECONDS}" "${log_file}" \
            backend prepare "${backend}" --source wheel --location "${current_tsfile_wheel}" || {
            status=$?
            log "TSFBenchmark backend prepare failed: backend=${backend}, log=${log_file}"
            return "${status}"
        }

        log_file="${tsfile_prepare_root}/inspect.$(safe_name "${backend}").log"
        run_tsfbench "${TSFILE_PREPARE_TIMEOUT_SECONDS}" "${log_file}" \
            backend inspect "${backend}" || {
            status=$?
            log "TSFBenchmark backend inspect failed: backend=${backend}, log=${log_file}"
            return "${status}"
        }
    done
}

# 执行当前 TSFile 候选版本的构建和安装准备。
prepare_current_tsfile_candidate() {
    tsfile_prepare_root="${TSFBENCH_GLOBAL_RESULT_ROOT}/${commit_date_time}_${commit_id}/prepare"
    build_tsfile_python_wheel || return $?
    prepare_candidate_tsfbench_backends
}

# 解析环境配置文件中的单条键值赋值。
load_env_assignment() {
    local raw_line="$1"
    local line=""
    local key=""
    local value=""

    line="${raw_line%$'\r'}"
    line="$(trim "${line}")"
    [ -n "${line}" ] || return 0
    case "${line}" in
        \#*) return 0 ;;
        export\ *) line="$(trim "${line#export }")" ;;
    esac

    [ "${line#*=}" != "${line}" ] || die "invalid env assignment in ${case_env_file}: ${raw_line}"
    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "invalid env key in ${case_env_file}: ${key}"

    case "${value}" in
        \"*\")
            value="${value#\"}"
            value="${value%\"}"
            ;;
        \'*\')
            value="${value#\'}"
            value="${value%\'}"
            ;;
    esac

    printf -v "${key}" '%s' "${value}"
    export "${key}"
}

# 加载用例环境文件并应用场景级配置。
load_case_env() {
    local env_name="$1"
    local raw_line=""

    reset_case_config
    case_env_file="${TSFBENCH_CASE_DIR}/${env_name}"
    [ -f "${case_env_file}" ] || die "missing TSFBench case env: ${case_env_file}"
    while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
        load_env_assignment "${raw_line}"
    done < "${case_env_file}"
    TSFBENCH_CASE_ID="${TSFBENCH_CASE_ID:-${env_name%.env}}"
    # Accept legacy case files that used release-looking selectors as placeholders.
    TSFBENCH_BACKENDS="${TSFBENCH_BACKENDS//tsfile@2.4.0+table/${tsfile_table_backend_selector}}"
    TSFBENCH_BACKENDS="${TSFBENCH_BACKENDS//tsfile@2.4.0+tree/${tsfile_tree_backend_selector}}"
    TSFBENCH_BACKENDS="${TSFBENCH_BACKENDS//tsfile@candidate+table/${tsfile_table_backend_selector}}"
    TSFBENCH_BACKENDS="${TSFBENCH_BACKENDS//tsfile@candidate+tree/${tsfile_tree_backend_selector}}"
    TSFBENCH_CODECS="${TSFBENCH_CODECS//tsfile@2.4.0+table/${tsfile_table_backend_selector}}"
    TSFBENCH_CODECS="${TSFBENCH_CODECS//tsfile@2.4.0+tree/${tsfile_tree_backend_selector}}"
    TSFBENCH_CODECS="${TSFBENCH_CODECS//tsfile@candidate+table/${tsfile_table_backend_selector}}"
    TSFBENCH_CODECS="${TSFBENCH_CODECS//tsfile@candidate+tree/${tsfile_tree_backend_selector}}"
}

# 校验用例必需配置及其取值格式。
validate_case_config() {
    [ -n "${TSFBENCH_MODALITY}" ] || die "missing TSFBENCH_MODALITY in ${case_env_file}"
    [ -n "${TSFBENCH_BACKENDS}" ] || die "missing TSFBENCH_BACKENDS in ${case_env_file}"

    case "${TSFBENCH_MODALITY}" in
        series_1d|grid_2d|point) ;;
        *) die "unsupported TSFBENCH_MODALITY=${TSFBENCH_MODALITY}" ;;
    esac

    if bool_enabled "${TSFBENCH_MICRO}" && [ "${TSFBENCH_MODALITY}" != "series_1d" ]; then
        die "--micro is only valid for series_1d"
    fi
    if bool_enabled "${TSFBENCH_MICRO}" && [ -n "${TSFBENCH_QUERY_FILE}" ]; then
        die "--micro cannot be combined with TSFBENCH_QUERY_FILE"
    fi
    if [ "${TSFBENCH_MODALITY}" = "point" ] && [ -n "${TSFBENCH_QUERY_FILE}" ]; then
        die "TSFBench point workloads use the built-in spatial query suite"
    fi
}

# 在参数数组中追加非空的可选命令行参数。
append_optional_arg() {
    local -n target_ref="$1"
    local option="$2"
    local value="$3"

    if [ -n "${value}" ]; then
        target_ref+=("${option}" "${value}")
    fi
}

# 将后端和编码器配置追加到 TSFBench 参数数组。
append_backend_args() {
    local -n target_ref="$1"
    local backend=""
    local codec=""
    local -a backends=()
    local -a codecs=()

    split_words "${TSFBENCH_BACKENDS}" backends
    for backend in "${backends[@]}"; do
        target_ref+=(--backend "${backend}")
    done

    split_words "${TSFBENCH_CODECS}" codecs
    for codec in "${codecs[@]}"; do
        target_ref+=(--codec "${codec}")
    done
}

# 根据当前用例配置构造 TSFBench run 参数列表。
build_run_args() {
    local -n args_ref="$1"
    local query_path=""
    local -a concurrency_values=()

    args_ref=(run --modality "${TSFBENCH_MODALITY}")
    append_optional_arg args_ref --suite "${TSFBENCH_SUITE}"
    append_backend_args args_ref

    if ! bool_enabled "${TSFBENCH_MICRO}"; then
        append_optional_arg args_ref --reference "${TSFBENCH_REFERENCE}"
    fi

    append_optional_arg args_ref --devices "${TSFBENCH_DEVICES}"
    append_optional_arg args_ref --sensors "${TSFBENCH_SENSORS}"
    append_optional_arg args_ref --times "${TSFBENCH_TIMES}"
    append_optional_arg args_ref --ny "${TSFBENCH_NY}"
    append_optional_arg args_ref --nx "${TSFBENCH_NX}"
    append_optional_arg args_ref --stations "${TSFBENCH_STATIONS}"
    append_optional_arg args_ref --density "${TSFBENCH_DENSITY}"
    append_optional_arg args_ref --missing-rate "${TSFBENCH_MISSING_RATE}"
    append_optional_arg args_ref --disorder "${TSFBENCH_DISORDER}"
    append_optional_arg args_ref --seed "${TSFBENCH_SEED}"
    append_optional_arg args_ref --repeat "${TSFBENCH_REPEAT}"
    append_optional_arg args_ref --warmup "${TSFBENCH_WARMUP}"
    append_optional_arg args_ref --iot-data-path "${TSFBENCH_IOT_DATA_PATH}"
    append_optional_arg args_ref --iot-timestamp-unit "${TSFBENCH_IOT_TIMESTAMP_UNIT}"
    append_optional_arg args_ref --iot-max-cells "${TSFBENCH_IOT_MAX_CELLS}"
    append_optional_arg args_ref --real "${TSFBENCH_REAL}"
    append_optional_arg args_ref --ghcn-element "${TSFBENCH_GHCN_ELEMENT}"
    append_optional_arg args_ref --ghcn-year-start "${TSFBENCH_GHCN_YEAR_START}"
    append_optional_arg args_ref --ghcn-year-end "${TSFBENCH_GHCN_YEAR_END}"

    if [ -n "${TSFBENCH_CONCURRENCY}" ]; then
        split_words "${TSFBENCH_CONCURRENCY}" concurrency_values
        if [ "${#concurrency_values[@]}" -gt 0 ]; then
            args_ref+=(--concurrency "${concurrency_values[@]}")
        fi
    fi

    if [ -n "${TSFBENCH_QUERY_FILE}" ]; then
        query_path="${TSFBENCH_QUERY_DIR}/${TSFBENCH_QUERY_FILE}"
        [ -f "${query_path}" ] || die "missing TSFBench query JSON: ${query_path}"
        args_ref+=(--queries-file "${query_path}")
    fi

    if bool_enabled "${TSFBENCH_MICRO}"; then
        args_ref+=(--micro)
    fi

    if bool_enabled "${TSFBENCH_KEEP_ARTIFACTS}"; then
        args_ref+=(--workdir "${case_workdir}")
    fi
    args_ref+=(--out "${case_result_csv}")
}

# 判断后端选择器是否需要预检或准备。
backend_needs_prepare_check() {
    case "$1" in
        *@*) return 0 ;;
        *) return 1 ;;
    esac
}

# 检查候选后端状态，并按配置执行准备流程。
prepare_or_verify_backends() {
    local backend=""
    local inspect_log=""
    local prepare_log=""
    local -a backends=()

    split_words "${TSFBENCH_BACKENDS}" backends
    for backend in "${backends[@]}"; do
        backend_needs_prepare_check "${backend}" || continue
        inspect_log="${case_log_file%.log}.inspect.$(safe_name "${backend}").log"
        if run_tsfbench "${TSFBENCH_PREPARE_TIMEOUT_SECONDS}" "${inspect_log}" backend inspect "${backend}"; then
            continue
        fi
        if bool_enabled "${TSFBENCH_PREPARE_BACKENDS}"; then
            prepare_log="${case_log_file%.log}.prepare.$(safe_name "${backend}").log"
            run_tsfbench "${TSFBENCH_PREPARE_TIMEOUT_SECONDS}" "${prepare_log}" backend prepare "${backend}" || return $?
            continue
        fi
        if bool_enabled "${TSFBENCH_REQUIRE_PREPARED}"; then
            log "backend is not prepared: ${backend}; set TSFBENCH_PREPARE_BACKENDS=1 to prepare it"
            return 40
        fi
    done
}

# 解析 TSFBench 结果 CSV 并输出标准化字段行。
parse_result_csv() {
    local csv_file="$1"

    awk -F, '
        BEGIN {
            sep = sprintf("%c", 31)
        }
        NR == 1 {
            for (i = 1; i <= NF; i++) {
                name = clean($i)
                header_idx[name] = i
            }
            next
        }
        NF > 1 {
            print clean(value("dataset")) sep \
                  clean(value("modality")) sep \
                  clean(value("format")) sep \
                  clean(value("query")) sep \
                  clean(value("n_repeat")) sep \
                  clean(value("p50_ms")) sep \
                  clean(value("p95_ms")) sep \
                  clean(value("p99_ms")) sep \
                  clean(value("min_ms")) sep \
                  clean(value("mean_ms")) sep \
                  clean(value("validated")) sep \
                  clean(value("stored_bytes")) sep \
                  clean(value("raw_bytes")) sep \
                  clean(value("compression_ratio")) sep \
                  clean(value("write_seconds")) sep \
                  clean(value("concurrency")) sep \
                  clean(value("throughput_qps")) sep \
                  clean(value("codec")) sep \
                  clean(value("codec_label")) sep \
                  clean(value("backend_id")) sep \
                  clean(value("backend_label")) sep \
                  clean(value("implementation")) sep \
                  clean(value("requested_version")) sep \
                  clean(value("resolved_version")) sep \
                  clean(value("profile")) sep \
                  clean(value("source_type")) sep \
                  clean(value("micro_elements")) sep \
                  clean(value("micro_stored_bytes")) sep \
                  clean(value("micro_decode_mbps"))
        }
        function value(name) {
            return (name in header_idx) ? $(header_idx[name]) : ""
        }
        function clean(value) {
            gsub(/\r/, "", value)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            gsub(/""/, "\"", value)
            return value
        }
    ' "${csv_file}"
}

# 将单条 TSFile 性能结果写入数据库。
insert_result_row() {
    local dataset="$1"
    local modality="$2"
    local format_name="$3"
    local query_name="$4"
    local n_repeat="$5"
    local p50_ms="$6"
    local p95_ms="$7"
    local p99_ms="$8"
    local min_ms="$9"
    shift 9
    local mean_ms="$1"
    local validated="$2"
    local stored_bytes="$3"
    local raw_bytes="$4"
    local compression_ratio="$5"
    local write_seconds="$6"
    local concurrency="$7"
    local throughput_qps="$8"
    local codec="$9"
    shift 9
    local codec_label="$1"
    local backend_id="$2"
    local backend_label="$3"
    local implementation="$4"
    local requested_version="$5"
    local resolved_version="$6"
    local profile="$7"
    local source_type="$8"
    local micro_elements="$9"
    shift 9
    local micro_stored_bytes="$1"
    local micro_decode_mbps="$2"
    local insert_sql=""
    local status=0

    insert_sql=$(cat <<EOF
insert into ${RESULT_TABLE_NAME} (
    commit_date_time,test_date_time,commit_id,author,
    case_id,case_env,case_title,modality,dataset,format_name,
    backend_id,backend_label,implementation,requested_version,resolved_version,
    profile,source_type,codec,codec_label,query_name,n_repeat,
    p50_ms,p95_ms,p99_ms,min_ms,mean_ms,validated,stored_bytes,raw_bytes,
    compression_ratio,write_seconds,concurrency,throughput_qps,
    micro_elements,micro_stored_bytes,micro_decode_mbps,
    start_time,end_time,cost_time,status,exit_code,
    result_csv,manifest_json,workdir,command_line,remark
) values (
    $(sql_datetime_or_null "${commit_date_time}"),
    $(sql_datetime_or_null "${test_date_time}"),
    $(sql_quote "${commit_id}"),
    $(sql_quote "${author}"),
    $(sql_quote "${case_id}"),
    $(sql_quote "${case_env_file}"),
    $(sql_text_or_null "${TSFBENCH_TITLE}"),
    $(sql_text_or_null "${modality}"),
    $(sql_text_or_null "${dataset}"),
    $(sql_text_or_null "${format_name}"),
    $(sql_text_or_null "${backend_id}"),
    $(sql_text_or_null "${backend_label}"),
    $(sql_text_or_null "${implementation}"),
    $(sql_text_or_null "${requested_version}"),
    $(sql_text_or_null "${resolved_version}"),
    $(sql_text_or_null "${profile}"),
    $(sql_text_or_null "${source_type}"),
    $(sql_text_or_null "${codec}"),
    $(sql_text_or_null "${codec_label}"),
    $(sql_text_or_null "${query_name}"),
    $(sql_int_or_null "${n_repeat}"),
    $(sql_number_or_null "${p50_ms}"),
    $(sql_number_or_null "${p95_ms}"),
    $(sql_number_or_null "${p99_ms}"),
    $(sql_number_or_null "${min_ms}"),
    $(sql_number_or_null "${mean_ms}"),
    $(sql_bool_or_null "${validated}"),
    $(sql_int_or_null "${stored_bytes}"),
    $(sql_int_or_null "${raw_bytes}"),
    $(sql_number_or_null "${compression_ratio}"),
    $(sql_number_or_null "${write_seconds}"),
    $(sql_int_or_null "${concurrency}"),
    $(sql_number_or_null "${throughput_qps}"),
    $(sql_int_or_null "${micro_elements}"),
    $(sql_number_or_null "${micro_stored_bytes}"),
    $(sql_number_or_null "${micro_decode_mbps}"),
    $(sql_quote "${case_start_time}"),
    $(sql_quote "${case_end_time}"),
    $(sql_int_or_null "${case_cost_time}"),
    $(sql_quote "${case_status}"),
    $(sql_int_or_null "${case_exit_code}"),
    $(sql_text_or_null "${case_result_csv}"),
    $(sql_text_or_null "${case_manifest_json}"),
    $(sql_text_or_null "${case_workdir}"),
    $(sql_text_or_null "${case_command_line}"),
    $(sql_text_or_null "${case_remark}")
)
EOF
)

    mysql_exec "${insert_sql}"
    status=$?
    if [ "${status}" -ne 0 ]; then
        log "failed to insert result row into ${RESULT_TABLE_NAME}: case=${case_id:-}, status=${status}"
        return "${status}"
    fi
}

# 解析结果 CSV 并逐行持久化测试数据。
persist_csv_results() {
    local parsed_line=""
    local rows=0
    local -a fields=()

    [ -f "${case_result_csv}" ] || return 1
    while IFS= read -r parsed_line; do
        IFS=$'\037' read -r -a fields <<< "${parsed_line}"
        while [ "${#fields[@]}" -lt 29 ]; do
            fields+=("")
        done
        insert_result_row "${fields[@]}" || return $?
        rows=$((rows + 1))
    done < <(parse_result_csv "${case_result_csv}")

    [ "${rows}" -gt 0 ]
}

# 持久化用例失败状态及错误说明。
persist_failure_result() {
    local failure_message="$1"
    local -a failure_fields=(
        "" "${TSFBENCH_MODALITY:-}" "" "case_failure" ""
        "" "" "" "" "" "False"
    )

    case_status="failed"
    case_remark="${failure_message}"
    while [ "${#failure_fields[@]}" -lt 29 ]; do
        failure_fields+=("")
    done
    insert_result_row "${failure_fields[@]}" || {
        local status=$?
        log "failed to persist failure result to ${RESULT_TABLE_NAME}: case=${case_id:-}, status=${status}, message=${failure_message}"
        return "${status}"
    }
}

# 持久化候选准备或测试阶段失败结果。
persist_stage_failure_result() {
    local stage="$1"
    local exit_code="$2"
    local message="$3"
    local stage_start_time="$4"
    local stage_end_time="$5"
    local persist_status=0

    reset_case_config
    case_id="${stage}"
    case_env_file=""
    case_result_csv=""
    case_manifest_json=""
    case_workdir="${tsfile_prepare_root}"
    case_log_file="${tsfile_prepare_root}/${stage}.log"
    case_command_line=""
    case_start_time="${stage_start_time}"
    case_end_time="${stage_end_time}"
    case_cost_time=$(( $(datetime_to_epoch "${case_end_time}") - $(datetime_to_epoch "${case_start_time}") ))
    case_status="failed"
    case_exit_code="${exit_code}"
    TSFBENCH_TITLE="${stage}"
    TSFBENCH_MODALITY="series_1d"
    persist_failure_result "${message}" || persist_status=$?
    if [ "${persist_status}" -ne 0 ]; then
        log "stage failure result was not written to ${RESULT_TABLE_NAME}: stage=${stage}"
    fi
    return "${persist_status}"
}

# 准备当前用例运行所需的 TSFile 候选阶段资源。
prepare_current_tsfile_candidate_stage() {
    local prepare_status=0
    local stage_start_time=""
    local stage_end_time=""

    stage_start_time="$(current_datetime)"
    prepare_current_tsfile_candidate || prepare_status=$?
    if [ "${prepare_status}" -ne 0 ]; then
        stage_end_time="$(current_datetime)"
        persist_stage_failure_result "tsfile_candidate_prepare" "${prepare_status}" \
            "TSFile candidate build/prepare failed, see ${tsfile_prepare_root}" \
            "${stage_start_time}" "${stage_end_time}"
        return "${prepare_status}"
    fi
    return 0
}

# 执行一个 TSFBench 用例并采集其结果或失败信息。
execute_case() {
    local matrix_case_id="$1"
    local env_name="$2"
    local status=0
    local -a args=()

    case_id="${matrix_case_id}"
    load_case_env "${env_name}"
    case_id="${TSFBENCH_CASE_ID:-${matrix_case_id}}"
    validate_case_config
    resolve_tsfbench_command || return $?

    case_start_time="$(current_datetime)"
    case_status="running"
    case_exit_code=0
    case_remark="${TSFBENCH_TITLE}"

    local case_root="${TSFBENCH_RESULT_ROOT}/${commit_date_time}_${commit_id}/${case_id}"
    case_result_csv="${case_root}/result.csv"
    case_manifest_json="$(manifest_path_for_csv "${case_result_csv}")"
    case_workdir="${case_root}/artifacts"
    case_log_file="${case_root}/tsfbench.log"
    mkdir -p "${case_root}" "${case_workdir}" "${TSFBENCH_HOME_DIR}"

    prepare_or_verify_backends
    status=$?
    if [ "${status}" -ne 0 ]; then
        case_exit_code="${status}"
        case_end_time="$(current_datetime)"
        case_cost_time=$(( $(datetime_to_epoch "${case_end_time}") - $(datetime_to_epoch "${case_start_time}") ))
        if ! persist_failure_result "backend prepare/inspect failed, see ${case_root}"; then
            log "backend failure result was not written to ${RESULT_TABLE_NAME}: case=${case_id}"
        fi
        return "${status}"
    fi

    build_run_args args
    case_command_line="$(format_command_line "${tsfbench_command[@]}" "${args[@]}")"
    log "run TSFBench case=${case_id} env=${env_name}"

    if run_tsfbench "${TSFBENCH_TIMEOUT_SECONDS}" "${case_log_file}" "${args[@]}"; then
        status=0
        case_status="done"
    else
        status=$?
        case_status="failed"
    fi

    case_exit_code="${status}"
    case_end_time="$(current_datetime)"
    case_cost_time=$(( $(datetime_to_epoch "${case_end_time}") - $(datetime_to_epoch "${case_start_time}") ))

    if [ "${status}" -eq 0 ] && persist_csv_results; then
        log "TSFBench case=${case_id} done, result=${case_result_csv}"
        return 0
    fi

    if [ "${status}" -eq 0 ]; then
        status=50
        case_exit_code="${status}"
    fi
    if ! persist_failure_result "TSFBench case failed or produced no parseable CSV, log=${case_log_file}"; then
        log "case failure result was not written to ${RESULT_TABLE_NAME}: case=${case_id}"
    fi
    return "${status}"
}

# 解析矩阵行并运行指定 TSFBench 用例。
run_case_row() {
    local row="$1"
    local matrix_case_id=""
    local env_name=""

    matrix_case_id="$(matrix_value "${row}" "case")" || return 20
    env_name="$(matrix_value "${row}" "env")" || return 20
    execute_case "${matrix_case_id}" "${env_name}"
}

# 遍历并执行场景中声明的全部本地用例。
run_all_cases_local() {
    local row=""
    local status=0
    local failed=0
    local executed=0
    local selected_case="${1:-}"

    while IFS= read -r row; do
        [ -n "${row}" ] || continue
        if [ -n "${selected_case}" ] && [ "$(matrix_value "${row}" "case")" != "${selected_case}" ]; then
            continue
        fi
        executed=$((executed + 1))
        run_case_row "${row}" || status=$?
        if [ "${status}" -ne 0 ]; then
            failed=1
            [ "${SCENARIO_FAILURE_POLICY}" = "fail_fast" ] && break
        fi
    done < <(scenario_cases_local)

    if [ -n "${selected_case}" ] && [ "${executed}" -eq 0 ]; then
        log "unknown case id: ${selected_case}"
        return 20
    fi

    [ "${failed}" -eq 0 ]
}

# 执行 TSFile 性能场景的独立主流程。
main() {
    local task_failed=0
    local selected_case=""
    local force_test="${TSFILE_FORCE_TEST}"
    local claim_status=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --list-cases)
                scenario_cases_local
                return 0
                ;;
            --case)
                shift
                selected_case="${1:-}"
                [ -n "${selected_case}" ] || die "--case requires a case id"
                ;;
            --force)
                force_test=1
                ;;
            *)
                die "usage: $0 [--list-cases|--case CASE_ID] [--force]"
                ;;
        esac
        shift || true
    done

    trap restore_test_type_file EXIT
    ensure_runtime_dependencies
    check_password
    mark_test_in_progress

    claim_current_tsfile_commit "${force_test}" || claim_status=$?
    if [ "${claim_status}" -eq 10 ]; then
        sleep "${TSFILE_NO_UPDATE_SLEEP_SECONDS}"
        return 0
    fi
    [ "${claim_status}" -eq 0 ] || return "${claim_status}"

    set_commit_scoped_tsfbench_home
    log "start ${TEST_TYPE}, commit=${commit_id}, test_date_time=${test_date_time}"

    if ! prepare_current_tsfile_candidate_stage; then
        task_failed=1
    elif ! run_all_cases_local "${selected_case}"; then
        task_failed=1
    fi

    return "${task_failed}"
}

# 准备 TSFile 场景环境并注册调度状态恢复操作。
scenario_task_prepare() { trap restore_test_type_file EXIT; ensure_runtime_dependencies; check_password; mark_test_in_progress; }
# 认领新 TSFile 提交并准备对应候选版本。
scenario_task_claim() { claim_current_tsfile_commit "${TSFILE_FORCE_TEST}" || return 1; set_commit_scoped_tsfbench_home; prepare_current_tsfile_candidate || return $?; TASK_CTX[commit_id]="${commit_id}"; TASK_CTX[author]="${author}"; TASK_CTX[commit_date_time]="${commit_date_time}"; }
# TSFile 场景不需要额外的任务运行状态写入。
scenario_task_mark_running() { :; }
# 执行当前用例及其对应环境配置。
scenario_case_execute() { execute_case "${CASE_CASE}" "${CASE_CTX[env]}"; }
# TSFile 场景成功收尾由框架统一处理。
scenario_task_finish_success() { :; }
# TSFile 场景失败收尾由框架统一处理。
scenario_task_finish_failure() { :; }

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
