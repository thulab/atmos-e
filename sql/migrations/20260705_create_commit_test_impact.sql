-- Store the precise-test decision made for each compiled commit.
-- Safe to run multiple times.

CREATE TABLE IF NOT EXISTS `commit_test_impact` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `commit_id` VARCHAR(64) NOT NULL,
    `commit_date_time` BIGINT DEFAULT NULL,
    `author` VARCHAR(128) DEFAULT NULL,
    `changed_file_count` INT NOT NULL DEFAULT 0,
    `changed_files` MEDIUMTEXT DEFAULT NULL,
    `matched_rules` TEXT DEFAULT NULL,
    `selected_tests` TEXT DEFAULT NULL,
    `skipped_tests` TEXT DEFAULT NULL,
    `fallback_reason` VARCHAR(512) DEFAULT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_commit_test_impact_commit` (`commit_id`),
    KEY `idx_commit_test_impact_time` (`commit_date_time`),
    KEY `idx_commit_test_impact_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
