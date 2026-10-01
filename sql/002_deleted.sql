-- Keep deletion intent after the business row is removed so seeds stay deleted.
CREATE TABLE IF NOT EXISTS `qbjobcreator_deleted` (
    `id` VARCHAR(64) NOT NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
