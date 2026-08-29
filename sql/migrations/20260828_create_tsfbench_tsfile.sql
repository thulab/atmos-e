-- Create the TSFBenchmark TsFile scenario status column and result table.
-- Safe to run multiple times.

SET @table_name = 'commit_history';
SET @column_name = 'tsfbench_tsfile';

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = @column_name
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `', @column_name, '` VARCHAR(32) DEFAULT NULL'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS `test_result_tsfbench_tsfile` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `commit_date_time` BIGINT DEFAULT NULL,
    `test_date_time` BIGINT DEFAULT NULL,
    `commit_id` VARCHAR(64) DEFAULT NULL,
    `author` VARCHAR(128) DEFAULT NULL,
    `case_id` VARCHAR(128) DEFAULT NULL,
    `case_env` VARCHAR(512) DEFAULT NULL,
    `case_title` VARCHAR(512) DEFAULT NULL,
    `modality` VARCHAR(32) DEFAULT NULL,
    `dataset` VARCHAR(128) DEFAULT NULL,
    `format_name` VARCHAR(64) DEFAULT NULL,
    `backend_id` VARCHAR(256) DEFAULT NULL,
    `backend_label` VARCHAR(512) DEFAULT NULL,
    `implementation` VARCHAR(128) DEFAULT NULL,
    `requested_version` VARCHAR(64) DEFAULT NULL,
    `resolved_version` VARCHAR(64) DEFAULT NULL,
    `profile` VARCHAR(64) DEFAULT NULL,
    `source_type` VARCHAR(64) DEFAULT NULL,
    `codec` VARCHAR(128) DEFAULT NULL,
    `codec_label` VARCHAR(256) DEFAULT NULL,
    `query_name` VARCHAR(256) DEFAULT NULL,
    `n_repeat` INT DEFAULT NULL,
    `p50_ms` DOUBLE DEFAULT NULL,
    `p95_ms` DOUBLE DEFAULT NULL,
    `p99_ms` DOUBLE DEFAULT NULL,
    `min_ms` DOUBLE DEFAULT NULL,
    `mean_ms` DOUBLE DEFAULT NULL,
    `validated` TINYINT(1) DEFAULT NULL,
    `stored_bytes` BIGINT DEFAULT NULL,
    `raw_bytes` BIGINT DEFAULT NULL,
    `compression_ratio` DOUBLE DEFAULT NULL,
    `write_seconds` DOUBLE DEFAULT NULL,
    `concurrency` INT DEFAULT NULL,
    `throughput_qps` DOUBLE DEFAULT NULL,
    `micro_elements` BIGINT DEFAULT NULL,
    `micro_stored_bytes` DOUBLE DEFAULT NULL,
    `micro_decode_mbps` DOUBLE DEFAULT NULL,
    `start_time` DATETIME DEFAULT NULL,
    `end_time` DATETIME DEFAULT NULL,
    `cost_time` BIGINT DEFAULT NULL,
    `status` VARCHAR(32) DEFAULT NULL,
    `exit_code` INT DEFAULT NULL,
    `result_csv` VARCHAR(1024) DEFAULT NULL,
    `manifest_json` VARCHAR(1024) DEFAULT NULL,
    `workdir` VARCHAR(1024) DEFAULT NULL,
    `command_line` TEXT DEFAULT NULL,
    `remark` TEXT DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_tsfbench_commit` (`commit_date_time`, `commit_id`),
    KEY `idx_tsfbench_test_date` (`test_date_time`),
    KEY `idx_tsfbench_case` (`case_id`),
    KEY `idx_tsfbench_backend_query` (`backend_id`, `query_name`),
    KEY `idx_tsfbench_profile_codec` (`profile`, `codec`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
