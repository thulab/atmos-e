# Atmos execution architecture

## Layers

- `framework/` owns validation, matrix expansion, hooks, context, and the
  Task/Run/Case lifecycle.
- `modules/` exposes stable task, IoTDB, Benchmark, monitor, result, backup,
  notification, and external-executor interfaces.
- `modules/scenarios/` contains scenario-specific implementations.
- `common/` remains the low-level compatibility layer while functions are
  progressively consumed through module interfaces.
- `scenarios/` contains only metadata, module selection, hooks, and
  `run_scenario`.

## Lifecycle

The Task lifecycle is the only owner of final task status. It claims a task,
marks it running, creates a Run, aggregates all Cases, and writes either success
or failure. Case code returns an error and never decides the final Task state.

Every Case traverses this phase order:

1. `case_prepare`
2. `iotdb_prepare`
3. `iotdb_configure`
4. `iotdb_start`
5. `benchmark_prepare`
6. `benchmark_execute`
7. `benchmark_wait`
8. `result_parse`
9. `monitor_collect`
10. `result_persist`
11. `runtime_stop`
12. `case_backup`

An implementation may provide a phase function directly. Consolidated mature
implementations use `scenario_case_execute` at `benchmark_execute`, while still
receiving all standard before/after phase hooks.

## Context

Modules exchange state through `TASK_CTX`, `RUN_CTX`, `CASE_CTX`, and
`RESULT_CTX`. Common case dimensions are exported as `CASE_PROTOCOL`,
`CASE_CASE`, `CASE_MODEL`, `CASE_WORKLOAD`, `CASE_API`, `CASE_QUERY`,
`CASE_DATA_TYPE`, `CASE_MODE`, `CASE_TYPE`, and `CASE_ATTEMPT`.

Case IDs are deterministic and preserve declared dimension order, for example:

```text
protocol=223__model=table__workload=seq_w
```

## Failure policy and codes

Scenarios select `fail_fast` or `continue_and_fail`. Generic implementation
failure maps to result error `50`; modules may return the standard codes:

- `10`: no task
- `20`: invalid configuration
- `30`: IoTDB start failure
- `40`: Benchmark start failure
- `41`: Benchmark timeout
- `50`: result/Case execution failure
- `60`: result persistence failure
- `70`: backup failure

## Result writers

Call `result_writer <schema> ...`. Available schemas are `ingestion`, `query`,
`compaction`, `pipe`, and `sql_coverage`. Writers own schema-specific field
ordering and delegate SQL execution through the database common layer.

## Adding a scenario

Declare `SCENARIO_ID`, `TASK_TEST_TYPE`, `SCENARIO_FAILURE_POLICY`, and either
`SCENARIO_CASE_DIMENSIONS` or explicit tab-separated `SCENARIO_CASES`. Source
the required implementation/module and `framework/runner.sh`, then invoke
`run_scenario`.

Run both repository checks before submitting:

```bash
bash tools/test_framework.sh
bash tools/check_scenario_architecture.sh
```

The architecture check rejects direct process startup, CLI execution,
recursive deletion, result SQL, task status SQL, and Benchmark startup from
scenario entry files.
