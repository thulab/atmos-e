-- Create the delete consistency test status column and result table.
-- Safe to run multiple times.

SET @table_name = 'commit_history';
SET @column_name = 'delete_test';

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

CREATE TABLE IF NOT EXISTS `test_result_delete_test` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `commit_date_time` BIGINT DEFAULT NULL,
    `test_date_time` BIGINT DEFAULT NULL,
    `commit_id` VARCHAR(128) DEFAULT NULL,
    `author` VARCHAR(128) DEFAULT NULL,
    `protocol` INT DEFAULT NULL,
    `pass_num` INT DEFAULT 0,
    `fail_num` INT DEFAULT 0,
    `write_ok_point` BIGINT DEFAULT 0,
    `write_ok_operation` BIGINT DEFAULT 0,
    `write_fail_point` BIGINT DEFAULT 0,
    `write_fail_operation` BIGINT DEFAULT 0,
    `delete_cost_ms_1` BIGINT DEFAULT 0,
    `delete_cost_ms_2` BIGINT DEFAULT 0,
    `delete_cost_ms_3` BIGINT DEFAULT 0,
    `pre_count` BIGINT DEFAULT 0,
    `delete1_window_count` BIGINT DEFAULT 0,
    `before_delete_window_count` BIGINT DEFAULT 0,
    `after_delete_window_count` BIGINT DEFAULT 0,
    `restart_delete1_window_count` BIGINT DEFAULT 0,
    `compacted_delete1_window_count` BIGINT DEFAULT 0,
    `compacted_before_count` BIGINT DEFAULT 0,
    `compacted_after_count` BIGINT DEFAULT 0,
    `compacted_total_count` BIGINT DEFAULT 0,
    `write_tsfile_count` BIGINT DEFAULT 0,
    `delete_mods_file_count` BIGINT DEFAULT 0,
    `compacted_level0_tsfile_count` BIGINT DEFAULT 0,
    `compacted_level1_tsfile_count` BIGINT DEFAULT 0,
    `compacted_mods_file_count` BIGINT DEFAULT 0,
    `numOfSe0Level` DOUBLE DEFAULT 0,
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
    `start_time` VARCHAR(32) DEFAULT NULL,
    `end_time` VARCHAR(32) DEFAULT NULL,
    `cost_time` BIGINT DEFAULT 0,
    `remark` TEXT DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_delete_commit` (`commit_date_time`, `commit_id`),
    KEY `idx_delete_test_date` (`test_date_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
