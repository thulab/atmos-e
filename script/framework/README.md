# Atmos scenario framework

The framework owns the Task, Run, and Case lifecycles. Scenario scripts declare
their matrix and provide adapters or hooks; only the outer Task lifecycle writes
the final task status.

## Scenario contract

A scenario declares `SCENARIO_ID`, `TASK_TEST_TYPE`,
`SCENARIO_CASE_DIMENSIONS`, and optionally `SCENARIO_FAILURE_POLICY`
(`fail_fast` or `continue_and_fail`). It then provides these module adapters:

- `scenario_task_prepare`
- `scenario_task_claim`
- `scenario_task_mark_running`
- `scenario_case_execute`
- `scenario_task_finish_success`
- `scenario_task_finish_failure`

Standard hooks include `scenario_validate`, `before_task`, `after_task`,
`before_run`, `after_run`, `before_case`, `after_case`, `on_case_failure`, and
`on_task_failure`. Phase-specific `before_<phase>` and `after_<phase>` hooks are
also supported.

The framework exposes `TASK_CTX`, `RUN_CTX`, `CASE_CTX`, and `RESULT_CTX`.
Matrix rows produce stable IDs such as
`protocol=223__case=tablemode__api=SESSION_BY_TABLET`.
Frequently used dimensions are also exposed as `CASE_PROTOCOL`, `CASE_CASE`,
`CASE_MODEL`, `CASE_WORKLOAD`, `CASE_API`, `CASE_QUERY`, and `CASE_ATTEMPT`.

`se_insert` and `unse_insert` are the first migrated scenarios. Their mature
IoTDB/Benchmark implementation remains in `common/insert_common.sh` while the
framework now owns matrix expansion, failure aggregation, and final task state.

Every case traverses the standard phase chain. Existing scenario implementations
are mounted at `benchmark_execute` until their individual operations need finer
hooks; new modules may implement any phase directly. Scenario entry files are
checked by `tools/check_scenario_architecture.sh` and cannot execute IoTDB,
Benchmark, SQL persistence, recursive deletion, or task status SQL directly.
