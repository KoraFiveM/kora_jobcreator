-- Migrated startup error paths emit the expected Kora.logging calls (spy), not print.
local H = dofile('test/harness.lua')
local eq = H.equal
local logged = {}
local function spy(level) return function(event, message, fields) logged[#logged + 1] = { level = level, event = event, message = message, fields = fields }; return true end end
local function newEnv(sqlReady, ensureResult, ensureErr)
    logged = {}
    local threads = {}
    Kora = {
        logging = { info = spy('info'), warn = spy('warn'), error = spy('error'), debug = spy('debug'), isEnabled = function() return true end },
        sql = { ready = function() return sqlReady end, ensureTables = function() return ensureResult, ensureErr end },
    }
    KoraJobCreatorTables = {}
    KoraJobCreator = { state = { ready = false, load = function() return true end, broadcast = function() end, businesses = {} },
        pos = { loadPrices = function() end }, logs = {}, staff = {} }
    CreateThread = function(fn) threads[#threads + 1] = fn end
    SetTimeout = function() end
    local chunk = assert(loadfile('server/main.lua'))
    local ok, err = pcall(chunk)
    return threads, ok, err
end

local threads = newEnv(false)
local ok, err = pcall(threads[1])
eq(ok, true, 'startup thread does not raise when SQL is unavailable: ' .. tostring(err))
eq(logged[1] and logged[1].level, 'error', 'SQL unavailable is an error')
eq(logged[1] and logged[1].event, 'sql.not_ready', 'SQL unavailable event name')
eq(KoraJobCreator.state.ready, false, 'resource stays disabled when SQL is unavailable')

threads = newEnv(true, nil, 'boom')
ok, err = pcall(threads[1])
eq(ok, true, 'startup thread does not raise on schema failure: ' .. tostring(err))
eq(logged[1] and logged[1].level, 'error', 'schema failure is an error')
eq(logged[1] and logged[1].event, 'schema.setup_failed', 'schema failure event name')
eq(logged[1] and logged[1].fields and logged[1].fields.error, 'boom', 'error text travels in fields, not the message')
eq(logged[1].message:find('boom', 1, true), nil, 'message stays static')
eq(KoraJobCreator.state.ready, false, 'resource stays disabled on schema failure')
H.finish('logging')
