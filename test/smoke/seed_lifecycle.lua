-- Actual startup/admin deletion lifecycle; host, SQL storage and periodic threads are inert.
local H = dofile('test/harness.lua')
local eq = H.equal
local root = ''
local statePath = arg[1] or 'server/state.lua'
local function read(path)
    local file = assert(io.open(path, 'rb'))
    local value = file:read('*a'); file:close(); return value
end
local stateSource = read(statePath)

local callbacks, published, exported, jobs, registrations, logs = {}, {}, {}, {}, {}, {}
local startupOrder = {}
Kora = {
    util = {}, compat = {},
    blips = { getCategoryIds = function() return { Business = 15, Restaurant = 34 } end },
    shared = {
        get = function(_, name) return jobs[name] end,
        all = function() return {} end,
    },
    callback = { register = function(name, fn, options)
        callbacks[name] = fn
        eq(type(options.rateLimit), 'table', 'real callbacks keep rate limits')
    end },
}
dofile('../kora_lib/modules/util/shared.lua')
local clone = Kora.util.deepClone
local encoded = {}
local function stable(value)
    if type(value) == 'string' then return ('%q'):format(value) end
    if type(value) ~= 'table' then return tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = stable(key) .. ':' .. stable(value[key]) end
    return '{' .. table.concat(parts, ',') .. '}'
end
json = {
    encode = function(value) local key = stable(value); encoded[key] = clone(value); return key end,
    decode = function(key) return clone(assert(encoded[key], 'unknown snapshot token')) end,
}
local rows, tombstones, statements = {}, {}, {}
local failNext, queryFail, markerFail, transactionFail = false, false, false, nil
local function driverExecute(_, sql, params, callback)
    statements[#statements + 1] = { kind = 'execute', sql = sql, params = clone(params) }
    if failNext then failNext = false; callback(nil, 'fixture write failure'); return end
    if sql:find('INSERT INTO `qbjobcreator`', 1, true) then
        local id = params[1]
        rows[id] = { id = id, label = params[2], job = params[3], modules = params[4] }
        callback({ affectedRows = 1 })
    elseif sql:find('DELETE FROM `qbjobcreator`', 1, true) then
        rows[params[1]] = nil; callback({ affectedRows = 1 })
    else error('unhandled inert SQL: ' .. sql) end
end
local function driverQuery(_, sql, ...)
    local args = { ... }; local callback = args[#args]
    statements[#statements + 1] = { kind = 'query', sql = sql }
    if queryFail then queryFail = false; callback(nil, 'fixture query failure'); return end
    local result = {}
    if sql:find('FROM `qbjobcreator_deleted`', 1, true) then
        startupOrder[#startupOrder + 1] = 'marker_query'
        if markerFail then markerFail = false; callback(nil, 'fixture marker query failure'); return end
        for id in pairs(tombstones) do result[#result + 1] = { id = id } end
    else
        startupOrder[#startupOrder + 1] = 'business_query'
        eq(sql:find('FROM `qbjobcreator`', 1, true) ~= nil, true, 'query stays within business persistence')
        for _, row in pairs(rows) do result[#result + 1] = clone(row) end
    end
    callback(result)
end
local function driverMigrate(_, resource, migrations, callback)
    startupOrder[#startupOrder + 1] = 'migrate'
    eq(resource, 'kora_jobcreator', 'actual main preserves migration resource name')
    eq(#migrations, 2, 'actual main registers both schema migrations')
    eq(migrations[1].version, 1, 'original migration version preserved')
    eq(migrations[1].checksum, Kora.util.fnv1a(migrations[1].sql), 'actual migrateFiles computes original migration checksum')
    eq(migrations[2].version, 2, 'new marker migration has additive version')
    eq(migrations[2].sql:find('CREATE TABLE IF NOT EXISTS `qbjobcreator_deleted`', 1, true) ~= nil, true,
        'new table migration uses existing retry-safe runner shape')
    eq(migrations[2].checksum, Kora.util.fnv1a(migrations[2].sql), 'actual migrateFiles fingerprints added file')
    callback({ ran = 2, total = 2 })
end
local function driverTransaction(_, queries, ...)
    local args = { ... }; local callback = args[#args]
    statements[#statements + 1] = { kind = 'transaction', queries = clone(queries) }
    if failNext then failNext = false; callback(nil, 'fixture write failure'); return end
    eq(#queries, 2, 'deletion uses two existing-provider transaction statements')
    local draftRows, draftTombstones = clone(rows), clone(tombstones)
    local failure = transactionFail; transactionFail = nil
    for index, statement in ipairs(queries) do
        if failure == index then callback(false); return end
        local sql, params = statement.sql, statement.params
        local id = params[1]
        if sql:find('DELETE FROM `qbjobcreator`', 1, true) then
            draftRows[id] = nil
        elseif sql:find('INSERT IGNORE INTO `qbjobcreator_deleted`', 1, true) then
            draftTombstones[id] = true
        else error('unexpected transaction SQL: ' .. sql) end
    end
    if failure == 'commit' then callback(false); return end
    rows, tombstones = draftRows, draftTombstones
    callback(true)
end
exports = setmetatable({
    kora_sql = { query = driverQuery, execute = driverExecute, transaction = driverTransaction,
        isReady = function() return true end, migrate = driverMigrate },
    kora_core = {
        hasPermission = function(_, src, permission) return src == 1 and permission == 'admin' end,
        registerShared = function(_, registry, name, value)
            eq(registry, 'jobs', 'seed job registry name is unchanged')
            jobs[name] = clone(value); return true
        end,
        getPlayerData = function() return nil end,
    },
    kora_inventory = {
        RegisterStash = function(_, id, label, slots, weight, owner, groups, coords, distance)
            registrations[id] = { label = label, coords = clone(coords), distance = distance }
        end,
    },
}, { __call = function(_, name, fn) exported[name] = fn end })
promise = { new = function()
    return {
        resolve = function(p, value) p.value = value; p.done = true end,
        reject = function(p, err) p.err = err; p.done = true end,
    }
end }
Citizen = { Await = function(p)
    assert(p.done, 'inert SQL callback must settle the promise')
    if p.err then error(p.err, 0) end
    return p.value
end }
dofile('../kora_sql/init.lua')
GetCurrentResourceName = function() return 'kora_jobcreator' end
LoadResourceFile = function(resource, path)
    eq(resource, 'kora_jobcreator', 'actual migrateFiles reads from owning resource')
    return read(root .. path)
end
RegisterNetEvent = function() end
TriggerClientEvent = function(name, target, snapshot)
    eq(name, 'qbjobcreator:client:sync', 'existing sync event unchanged')
    published[#published + 1] = { target = target, snapshot = clone(snapshot) }
end
dofile(root .. 'config.lua')
dofile(root .. 'shared/schema.lua')
dofile(root .. 'shared/businesses/burgershot.lua')
local function boot()
    assert(load(stateSource, '@' .. statePath))()
    startupOrder = {}
    QbJobCreator.pos = { register = function() end, resetBusiness = function() end,
        loadPrices = function() startupOrder[#startupOrder + 1] = 'prices' end }
    QbJobCreator.crafting = { registerUseable = function() end }
    QbJobCreator.staff = { counts = function() return {} end }
    QbJobCreator.logs = { record = function(business, entry)
        logs[#logs + 1] = { id = business.id, entry = clone(entry) }
    end }
    dofile(root .. 'server/register.lua')
    dofile(root .. 'server/admin.lua')
    local State = QbJobCreator.state
    local threads = {}
    CreateThread = function(fn) threads[#threads + 1] = fn end
    dofile(root .. 'server/main.lua')
    eq(#threads, 2, 'actual main queues startup and log trimming separately')
    eq(State.ready, false, 'actual main leaves readiness false before startup')
    threads[1]() -- Leave the unrelated periodic log loop inert.
    eq(State.ready, true, 'actual main marks ready after successful migration and load')
    eq(startupOrder[1], 'migrate', 'schema migration occurs before persisted data reads')
    eq(startupOrder[2], 'prices', 'existing price load order preserved')
    eq(startupOrder[3], 'business_query', 'actual state loads after migration completion')
    return State
end
local State = boot()
eq(State.get('burgershot').label, 'Burger Shot', 'fresh installation seeds demo')
eq(#State.get('burgershot').modules, 6, 'shipped modules pass actual validator')
eq(rows.burgershot.label, 'Burger Shot', 'seed is durably represented by inert row')
eq(type(jobs.burgershot), 'table', 'seed job registered on first boot')
local deleted = callbacks['qbjobcreator:server:deleteBusiness']
eq(deleted(2, 'burgershot'), false, 'non-admin cannot delete seed')
eq(State.get('burgershot') ~= nil, true, 'unauthorized delete preserves live seed')
eq(callbacks['qbjobcreator:server:editBusiness'](1, 'burgershot', { label = 'Edited in game' }), true, 'admin edit succeeds')
local editedRev = State.get('burgershot').rev
State = boot()
eq(State.get('burgershot').label, 'Edited in game', 'restart preserves legitimate edited seed')
eq(State.get('burgershot').rev, editedRev, 'definition fingerprint survives reload')
local publicationCount = #published
failNext = true
local ok, err = callbacks['qbjobcreator:server:deleteBusiness'](1, 'burgershot')
eq(ok, false, 'SQL failure rejects delete')
eq(err, 'Could not delete the business.', 'existing delete failure message preserved')
eq(#published, publicationCount, 'failed delete emits no replacement world')
eq(State.get('burgershot').label, 'Edited in game', 'failed delete leaves live state unchanged')
eq(rows.burgershot.label, 'Edited in game', 'failed delete leaves stored definition unchanged')
do
    for _, failure in ipairs({ 1, 2, 'commit' }) do
        transactionFail = failure
        publicationCount = #published
        local failed, failureErr = callbacks['qbjobcreator:server:deleteBusiness'](1, 'burgershot')
        eq(failed, false, 'transaction false without error rejects deletion at ' .. tostring(failure))
        eq(failureErr, 'Could not delete the business.', 'transaction failure preserves useful public reason')
        eq(State.get('burgershot').label, 'Edited in game', 'transaction failure keeps live definition')
        eq(rows.burgershot.label, 'Edited in game', 'transaction failure keeps stored definition')
        eq(tombstones.burgershot, nil, 'transaction failure does not leak deletion marker')
        eq(#published, publicationCount, 'transaction failure emits no sync')
    end
end
eq(callbacks['qbjobcreator:server:deleteBusiness'](1, 'burgershot'), true, 'authorized delete reports success')
eq(State.get('burgershot'), nil, 'deleted seed absent from current provider')
eq(#exported.getBusinesses(), 0, 'deleted seed absent from public snapshot')
eq(exported.getBusiness('burgershot'), nil, 'deleted seed absent from individual public export')
eq(logs[#logs].entry.message, 'Deleted business Edited in game.', 'existing admin audit contract unchanged')
eq(rows.burgershot, nil, 'successful delete preserves original hard-delete row semantics')
jobs = {} -- Model kora_core restarting with the resource: job registrations are volatile.
State = boot()
eq(State.get('burgershot') ~= nil, false, 'deleted seed must remain absent after fresh module load')
eq(type(jobs.burgershot), 'table', 'seed jobs are re-registered independently on later boots')
eq(#exported.getBusinesses(), 0, 'restart public snapshot matches deletion lifetime')
local id = callbacks['qbjobcreator:server:createBusiness'](1, { id = 'burgershot', label = 'Recreated manually', job = 'burgershot' })
eq(id, 'burgershot', 'existing admin create contract permits explicit recreation of same id')
eq(State.get('burgershot').label, 'Recreated manually', 'explicit recreation becomes live')
eq(tombstones.burgershot, true, 'explicit recreation retains only the automatic-seed suppression marker')
State = boot()
eq(State.get('burgershot').label, 'Recreated manually', 'manual recreation survives restart without seed overwrite')
eq(#State.get('burgershot').modules, 0, 'seed modules do not replace manually recreated empty module list')
eq(callbacks['qbjobcreator:server:deleteBusiness'](1, 'burgershot'), true, 'recreated seed can be deleted again')
State = boot()
eq(State.get('burgershot') ~= nil, false, 'second restart retains the same deletion policy')
local manual = callbacks['qbjobcreator:server:createBusiness'](1, { id = 'manual', label = 'Manual', job = 'burgershot' })
eq(manual, 'manual', 'unseeded business can still be created')
eq(callbacks['qbjobcreator:server:deleteBusiness'](1, 'manual'), true, 'unseeded business can still be deleted')
State = boot()
eq(State.get('manual'), nil, 'unseeded deleted business remains absent in control')
Config.seeds[#Config.seeds + 1] = { id = 'new_seed', label = 'New seed after install', job = 'burgershot', modules = {} }
State = boot()
eq(State.get('new_seed').label, 'New seed after install', 'new configured seed remains eligible on existing installation')
eq(callbacks['qbjobcreator:server:deleteBusiness'](1, 'new_seed'), true, 'new configured seed is deletable')
State = boot()
eq(State.get('new_seed') ~= nil, false, 'new configured seed respects deletion on later startup')
local configuredSeeds = Config.seeds
Config.seeds = {}
State = boot()
Config.seeds = configuredSeeds
State = boot()
eq(State.get('burgershot') ~= nil, false, 'removing and restoring seed config preserves durable deletion intent')
eq(State.get('new_seed') ~= nil, false, 'newly introduced seed suppression persists across config reload')
do
    local mirrorBefore = State.businesses
    publicationCount = #published
    markerFail = true
    local loadOK, loadErr = State.load()
    eq(loadOK, false, 'marker query failure rejects startup instead of allowing reseeding')
    eq(loadErr, 'fixture marker query failure', 'marker query failure preserves provider reason')
    eq(State.businesses, mirrorBefore, 'marker query failure occurs before mirror mutation')
    eq(#published, publicationCount, 'marker query failure publishes no unsafe snapshot')
end
local beforeFailure = State.businesses
queryFail = true
local loadOK, loadErr = State.load()
eq(loadOK, false, 'business query failure rejects startup load')
eq(loadErr, 'fixture query failure', 'actual qbsql wrapper preserves failure reason')
eq(State.businesses, beforeFailure, 'failed query leaves existing mirror alone')
H.finish('seed_lifecycle')
