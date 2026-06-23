-- Add staged file-count metrics for delete consistency test results.
-- Safe to run multiple times after test_result_delete_test has been created.

SET @table_name = 'test_result_delete_test';

SET @column_name = 'write_tsfile_count';
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
        '` ADD COLUMN `', @column_name,
        '` BIGINT DEFAULT 0 AFTER `compacted_total_count`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @column_name = 'delete_mods_file_count';
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
        '` ADD COLUMN `', @column_name,
        '` BIGINT DEFAULT 0 AFTER `write_tsfile_count`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @column_name = 'compacted_level0_tsfile_count';
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
        '` ADD COLUMN `', @column_name,
        '` BIGINT DEFAULT 0 AFTER `delete_mods_file_count`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @column_name = 'compacted_level1_tsfile_count';
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
        '` ADD COLUMN `', @column_name,
        '` BIGINT DEFAULT 0 AFTER `compacted_level0_tsfile_count`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @column_name = 'compacted_mods_file_count';
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
        '` ADD COLUMN `', @column_name,
        '` BIGINT DEFAULT 0 AFTER `compacted_level1_tsfile_count`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
