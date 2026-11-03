QBJobCreatorTables = {
    {
        name = 'qbjobcreator',
        collate = 'utf8mb4_unicode_ci',
        columns = {
            { name = 'id', type = 'varchar(64)' },
            { name = 'label', type = 'varchar(128)' },
            { name = 'job', type = 'varchar(64)' },
            { name = 'modules', type = 'longtext' },
            { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
            { name = 'updated_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' }, on_update = 'CURRENT_TIMESTAMP' },
        },
        primary = { 'id' },
        indexes = {
            { name = 'qbjobcreator_job', columns = { 'job' } },
        },
    },
    {
        name = 'qbjobcreator_prices',
        collate = 'utf8mb4_unicode_ci',
        columns = {
            { name = 'shop', type = 'varchar(64)' },
            { name = 'item', type = 'varchar(64)' },
            { name = 'price', type = 'int', unsigned = true },
            { name = 'updated_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' }, on_update = 'CURRENT_TIMESTAMP' },
        },
        primary = { 'shop', 'item' },
    },
    {
        name = 'qbjobcreator_logs',
        collate = 'utf8mb4_unicode_ci',
        columns = {
            { name = 'id', type = 'bigint', unsigned = true, auto_increment = true },
            { name = 'business', type = 'varchar(64)' },
            { name = 'category', type = 'varchar(32)' },
            { name = 'message', type = 'varchar(512)' },
            { name = 'citizenid', type = 'varchar(64)', null = true, default = Kora.sql.NULL },
            { name = 'amount', type = 'int', null = true, default = Kora.sql.NULL },
            { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
        },
        primary = { 'id' },
        indexes = {
            { name = 'qbjobcreator_logs_business', columns = { 'business', 'id' } },
        },
    },
    {
        name = 'qbjobcreator_deleted',
        collate = 'utf8mb4_unicode_ci',
        columns = {
            { name = 'id', type = 'varchar(64)' },
        },
        primary = { 'id' },
    },
}
