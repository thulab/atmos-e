-- Create the longrun upgrade test status column and result table.
-- Safe to run multiple times.

SET @table_name = 'commit_history';
SET @column_name = 'longrun_test';

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

CREATE TABLE IF NOT EXISTS `test_result_longrun_test` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `commit_date_time` BIGINT DEFAULT NULL,
    `test_date_time` BIGINT DEFAULT NULL,
    `commit_id` VARCHAR(64) DEFAULT NULL,
    `author` VARCHAR(128) DEFAULT NULL,
    `ts_type` VARCHAR(128) DEFAULT NULL,
    `data_type` VARCHAR(128) DEFAULT NULL,
    `op_type` VARCHAR(128) DEFAULT NULL,
    `okPoint` DOUBLE DEFAULT 0,
    `okOperation` DOUBLE DEFAULT 0,
    `failPoint` DOUBLE DEFAULT 0,
    `failOperation` DOUBLE DEFAULT 0,
    `throughput` DOUBLE DEFAULT 0,
    `Latency` DOUBLE DEFAULT 0,
    `MIN` DOUBLE DEFAULT 0,
    `P10` DOUBLE DEFAULT 0,
    `P25` DOUBLE DEFAULT 0,
    `MEDIAN` DOUBLE DEFAULT 0,
    `P75` DOUBLE DEFAULT 0,
    `P90` DOUBLE DEFAULT 0,
    `P95` DOUBLE DEFAULT 0,
    `P99` DOUBLE DEFAULT 0,
    `P999` DOUBLE DEFAULT 0,
    `MAX` DOUBLE DEFAULT 0,
    `numOfSe0Level` DOUBLE DEFAULT 0,
    `start_time` DATETIME DEFAULT NULL,
    `end_time` DATETIME DEFAULT NULL,
    `cost_time` BIGINT DEFAULT 0,
    `numOfUnse0Level` DOUBLE DEFAULT 0,
    `dataFileSize` DOUBLE DEFAULT 0,
    `maxNumofOpenFiles` DOUBLE DEFAULT 0,
    `maxNumofThread` DOUBLE DEFAULT 0,
    `errorLogSize` DOUBLE DEFAULT 0,
    `walFileSize` DOUBLE DEFAULT 0,
    `avgCPULoad` DOUBLE DEFAULT 0,
    `maxCPULoad` DOUBLE DEFAULT 0,
    `maxDiskIOSizeRead` DOUBLE DEFAULT 0,
    `maxDiskIOSizeWrite` DOUBLE DEFAULT 0,
    `maxDiskIOOpsRead` DOUBLE DEFAULT 0,
    `maxDiskIOOpsWrite` DOUBLE DEFAULT 0,
    `protocol_code` VARCHAR(32) DEFAULT NULL,
    `benchmark_id` VARCHAR(128) DEFAULT NULL,
    `benchmark_label` VARCHAR(128) DEFAULT NULL,
    `result_kind` VARCHAR(32) DEFAULT NULL,
    `upgrade_from_commit_id` VARCHAR(64) DEFAULT NULL,
    `upgrade_from_commit_date_time` BIGINT DEFAULT NULL,
    `remark` VARCHAR(512) DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_longrun_commit` (`commit_date_time`, `commit_id`),
    KEY `idx_longrun_test_date` (`test_date_time`),
    KEY `idx_longrun_benchmark` (`benchmark_id`, `benchmark_label`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
