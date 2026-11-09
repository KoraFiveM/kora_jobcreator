fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_jobcreator'
-- Keep the legacy resource name resolvable for exports['qbjobcreator'] callers.
provide 'qbjobcreator'
author 'qbcore2'
version '1.0.0'
description 'kora_lib-native in-game job and business creator'

dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'
dependency 'kora_inventory'
dependency 'kora_target'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_core/init.lua',
    'config.lua',
    'shared/schema.lua',
    'shared/recipes/*.lua',
    'shared/shopitems/*.lua',
    'shared/businesses/*.lua',
    'shared/config_registration.lua',
}

-- Load order is deliberate: `state` owns the registry every other file reads,
-- and `main` runs the boot sequence once the rest have registered themselves.
server_scripts {
    '@kora_sql/init.lua',
    'server/config.lua',
    'server/state.lua',
    'server/logs.lua',
    'server/staff.lua',
    'server/pos.lua',
    'server/crafting.lua',
    'server/payment.lua',
    'server/register.lua',
    'server/admin.lua',
    'server/tables.lua',
    'server/main.lua',
}

client_scripts {
    'client/state.lua',
    'client/business.lua',
    'client/payment.lua',
    'client/creator.lua',
    'client/main.lua',
}

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
