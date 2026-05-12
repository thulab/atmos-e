-- Unify metadata columns for insert-task result tables.
-- Safe to run multiple times.

SET @table_name = 'test_result_se_insert';

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'protocol_code'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `protocol_code` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `protocol`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_case_id'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_case_id` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `ts_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_layout_type'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_layout_type` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `insert_case_id`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_write_mode'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_write_mode` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `insert_layout_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'result_kind'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `result_kind` VARCHAR(32) NOT NULL DEFAULT ''ingestion'' AFTER `insert_write_mode`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE `test_result_se_insert`
SET `protocol_code` = CASE
        WHEN `protocol_code` IS NULL OR `protocol_code` = '' THEN CAST(`protocol` AS CHAR)
        ELSE `protocol_code`
    END,
    `insert_case_id` = CASE
        WHEN `insert_case_id` IS NULL OR `insert_case_id` = '' THEN `ts_type`
        ELSE `insert_case_id`
    END,
    `insert_layout_type` = CASE
        WHEN `insert_layout_type` IS NOT NULL AND `insert_layout_type` <> '' THEN `insert_layout_type`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_rw'))
        WHEN `ts_type` LIKE '%_unseq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_w'))
        WHEN `ts_type` LIKE '%_seq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_rw'))
        WHEN `ts_type` LIKE '%_seq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_w'))
        ELSE `ts_type`
    END,
    `insert_write_mode` = CASE
        WHEN `insert_write_mode` IS NOT NULL AND `insert_write_mode` <> '' THEN `insert_write_mode`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN 'unseq_rw'
        WHEN `ts_type` LIKE '%_unseq_w' THEN 'unseq_w'
        WHEN `ts_type` LIKE '%_seq_rw' THEN 'seq_rw'
        WHEN `ts_type` LIKE '%_seq_w' THEN 'seq_w'
        ELSE ''
    END,
    `result_kind` = CASE
        WHEN `result_kind` IS NULL OR `result_kind` = '' THEN 'ingestion'
        ELSE `result_kind`
    END;

SET @table_name = 'test_result_unse_insert';

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'protocol_code'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `protocol_code` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `protocol`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_case_id'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_case_id` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `ts_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_layout_type'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_layout_type` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `insert_case_id`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_write_mode'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_write_mode` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `insert_layout_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'result_kind'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `result_kind` VARCHAR(32) NOT NULL DEFAULT ''ingestion'' AFTER `insert_write_mode`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE `test_result_unse_insert`
SET `protocol_code` = CASE
        WHEN `protocol_code` IS NULL OR `protocol_code` = '' THEN CAST(`protocol` AS CHAR)
        ELSE `protocol_code`
    END,
    `insert_case_id` = CASE
        WHEN `insert_case_id` IS NULL OR `insert_case_id` = '' THEN `ts_type`
        ELSE `insert_case_id`
    END,
    `insert_layout_type` = CASE
        WHEN `insert_layout_type` IS NOT NULL AND `insert_layout_type` <> '' THEN `insert_layout_type`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_rw'))
        WHEN `ts_type` LIKE '%_unseq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_w'))
        WHEN `ts_type` LIKE '%_seq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_rw'))
        WHEN `ts_type` LIKE '%_seq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_w'))
        ELSE `ts_type`
    END,
    `insert_write_mode` = CASE
        WHEN `insert_write_mode` IS NOT NULL AND `insert_write_mode` <> '' THEN `insert_write_mode`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN 'unseq_rw'
        WHEN `ts_type` LIKE '%_unseq_w' THEN 'unseq_w'
        WHEN `ts_type` LIKE '%_seq_rw' THEN 'seq_rw'
        WHEN `ts_type` LIKE '%_seq_w' THEN 'seq_w'
        ELSE ''
    END,
    `result_kind` = CASE
        WHEN `result_kind` IS NULL OR `result_kind` = '' THEN 'ingestion'
        ELSE `result_kind`
    END;

SET @table_name = 'test_result_weeklytest_insert';

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'protocol_code'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `protocol_code` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `protocol`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_case_id'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_case_id` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `ts_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_layout_type'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_layout_type` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `insert_case_id`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_write_mode'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_write_mode` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `insert_layout_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'result_kind'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `result_kind` VARCHAR(32) NOT NULL DEFAULT ''ingestion'' AFTER `insert_write_mode`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE `test_result_weeklytest_insert`
SET `protocol_code` = CASE
        WHEN `protocol_code` IS NULL OR `protocol_code` = '' THEN CAST(`protocol` AS CHAR)
        ELSE `protocol_code`
    END,
    `insert_case_id` = CASE
        WHEN `insert_case_id` IS NULL OR `insert_case_id` = '' THEN `ts_type`
        ELSE `insert_case_id`
    END,
    `insert_layout_type` = CASE
        WHEN `insert_layout_type` IS NOT NULL AND `insert_layout_type` <> '' THEN `insert_layout_type`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_rw'))
        WHEN `ts_type` LIKE '%_unseq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_w'))
        WHEN `ts_type` LIKE '%_seq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_rw'))
        WHEN `ts_type` LIKE '%_seq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_w'))
        ELSE `ts_type`
    END,
    `insert_write_mode` = CASE
        WHEN `insert_write_mode` IS NOT NULL AND `insert_write_mode` <> '' THEN `insert_write_mode`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN 'unseq_rw'
        WHEN `ts_type` LIKE '%_unseq_w' THEN 'unseq_w'
        WHEN `ts_type` LIKE '%_seq_rw' THEN 'seq_rw'
        WHEN `ts_type` LIKE '%_seq_w' THEN 'seq_w'
        ELSE ''
    END,
    `result_kind` = CASE
        WHEN `result_kind` IS NULL OR `result_kind` = '' THEN 'ingestion'
        ELSE `result_kind`
    END;

SET @table_name = 'test_result_api_insert';

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'protocol_code'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `protocol_code` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `protocol`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_case_id'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_case_id` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `ts_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_layout_type'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_layout_type` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `insert_case_id`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_write_mode'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_write_mode` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `insert_layout_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'result_kind'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `result_kind` VARCHAR(32) NOT NULL DEFAULT ''ingestion'' AFTER `insert_write_mode`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE `test_result_api_insert`
SET `protocol_code` = CASE
        WHEN `protocol_code` IS NULL OR `protocol_code` = '' THEN CAST(`protocol` AS CHAR)
        ELSE `protocol_code`
    END,
    `insert_case_id` = CASE
        WHEN `insert_case_id` IS NULL OR `insert_case_id` = '' THEN `ts_type`
        ELSE `insert_case_id`
    END,
    `insert_layout_type` = CASE
        WHEN `insert_layout_type` IS NOT NULL AND `insert_layout_type` <> '' THEN `insert_layout_type`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_rw'))
        WHEN `ts_type` LIKE '%_unseq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_w'))
        WHEN `ts_type` LIKE '%_seq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_rw'))
        WHEN `ts_type` LIKE '%_seq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_w'))
        ELSE `ts_type`
    END,
    `insert_write_mode` = CASE
        WHEN `insert_write_mode` IS NOT NULL AND `insert_write_mode` <> '' THEN `insert_write_mode`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN 'unseq_rw'
        WHEN `ts_type` LIKE '%_unseq_w' THEN 'unseq_w'
        WHEN `ts_type` LIKE '%_seq_rw' THEN 'seq_rw'
        WHEN `ts_type` LIKE '%_seq_w' THEN 'seq_w'
        ELSE ''
    END,
    `result_kind` = CASE
        WHEN `result_kind` IS NULL OR `result_kind` = '' THEN 'ingestion'
        ELSE `result_kind`
    END;

SET @table_name = 'test_result_api_insert_cts';

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'protocol_code'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `protocol_code` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `protocol`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_case_id'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_case_id` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `ts_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_layout_type'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_layout_type` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `insert_case_id`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'insert_write_mode'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `insert_write_mode` VARCHAR(32) NOT NULL DEFAULT '''' AFTER `insert_layout_type`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT IF(
    EXISTS(
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = @table_name
          AND column_name = 'result_kind'
    ),
    'SELECT 1',
    CONCAT(
        'ALTER TABLE `', @table_name,
        '` ADD COLUMN `result_kind` VARCHAR(32) NOT NULL DEFAULT ''ingestion'' AFTER `insert_write_mode`'
    )
) INTO @ddl;
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE `test_result_api_insert_cts`
SET `protocol_code` = CASE
        WHEN `protocol_code` IS NULL OR `protocol_code` = '' THEN CAST(`protocol` AS CHAR)
        ELSE `protocol_code`
    END,
    `insert_case_id` = CASE
        WHEN `insert_case_id` IS NULL OR `insert_case_id` = '' THEN `ts_type`
        ELSE `insert_case_id`
    END,
    `insert_layout_type` = CASE
        WHEN `insert_layout_type` IS NOT NULL AND `insert_layout_type` <> '' THEN `insert_layout_type`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_rw'))
        WHEN `ts_type` LIKE '%_unseq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_unseq_w'))
        WHEN `ts_type` LIKE '%_seq_rw' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_rw'))
        WHEN `ts_type` LIKE '%_seq_w' THEN LEFT(`ts_type`, CHAR_LENGTH(`ts_type`) - CHAR_LENGTH('_seq_w'))
        ELSE `ts_type`
    END,
    `insert_write_mode` = CASE
        WHEN `insert_write_mode` IS NOT NULL AND `insert_write_mode` <> '' THEN `insert_write_mode`
        WHEN `ts_type` LIKE '%_unseq_rw' THEN 'unseq_rw'
        WHEN `ts_type` LIKE '%_unseq_w' THEN 'unseq_w'
        WHEN `ts_type` LIKE '%_seq_rw' THEN 'seq_rw'
        WHEN `ts_type` LIKE '%_seq_w' THEN 'seq_w'
        ELSE ''
    END,
    `result_kind` = CASE
        WHEN `result_kind` IS NULL OR `result_kind` = '' THEN 'ingestion'
        ELSE `result_kind`
    END;
