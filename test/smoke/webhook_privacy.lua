-- Actual public replication and authorized creator edits; host, SQL and URLs are inert.
local H = dofile('test/harness.lua')
local check = H.ok
local resource = arg[1] or '.'
local function noop() end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local secret, replacement = 'https://example.invalid/FAKE-hook-token', 'https://example.invalid/FAKE-new-token'
local encoded, serial = {}, 0
local codec = {
    encode = function(value) serial = serial + 1; local id = tostring(serial); encoded[id] = copy(value); return id end,
    decode = function(id) return copy(encoded[id]) end,
}
local server = {}; for name, value in pairs(_G) do server[name] = value end
local callbacks, registered, syncs, persisted = {}, {}, {}, {}
local currentClient, clientHandlers = 3, {}
local adminAllowed = true
local players = { [1] = { job = { name = 'shop', grade = { level = 0 } } },
    [2] = { job = { name = 'shop', grade = { level = 1 } } },
    [3] = { job = { name = 'police', grade = { level = 0 } } } }
server.GetCurrentResourceName = function() return 'kora_jobcreator' end
server.GetResourceState = function() return 'stopped' end
server.GetPlayerPed = function(src) return src end
server.json = codec
server.Kora = {
    util = {}, compat = {}, blips = { getCategoryIds = function() return {} end },
    callback = { register = function(name, handler, options) callbacks[name] = { handler = handler, options = options } end },
    shared = { get = function(_, name) return { name = name, grades = { [1] = { isboss = true } } } end, all = function() return {} end },
    sql = {
        execute = function(_, params) persisted[params[1]] = codec.decode(params[4]); return true end,
        transaction = function(queries)
            for _, query in ipairs(queries) do
                if query.sql:find('DELETE FROM `kora_jobcreator`', 1, true) then persisted[query.params[1]] = nil end
            end
            return true
        end,
    },
}
server.KoraJobCreator = {
    register = { business = noop, removeBusiness = noop }, staff = { counts = function() return {} end },
    logs = { record = noop, recent = function() return {} end },
}
server.exports = setmetatable({ kora_core = {
    getPlayerData = function(_, src) return players[src] end,
    hasPermission = function(_, src) return src == 1 and adminAllowed end,
} }, { __call = function(_, name, handler) registered[name] = handler end })
server.TriggerClientEvent = function(name, target, payload)
    syncs[#syncs + 1] = { name = name, target = target, payload = copy(payload) }
    if (target == -1 or target == currentClient) and clientHandlers[name] then clientHandlers[name](copy(payload)) end
end
local function load(path, env) assert(loadfile(path, 't', env))() end
load('../kora_lib/modules/util/shared.lua', server)
load('config.lua', server); load('shared/schema.lua', server)
load(resource .. '/server/state.lua', server); load(resource .. '/server/admin.lua', server)
local State = server.KoraJobCreator.state
State.ready = true
local function call(src, name, ...) return assert(callbacks['kora_jobcreator:server:' .. name], 'missing callback ' .. name).handler(src, ...) end
local business = assert(State.persist({ id = 'shop', label = 'Shop', job = 'shop', modules = {
    { moduleType = 'POS', id = 'front_till', label = 'Till', zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 }, radius = 1,
        webhook = secret, commission = 10, items = {} },
} }))
check(business.modules[1].webhook == secret and persisted.shop[1].webhook == secret, 'real schema and persistence retain fake server webhook')
local ordinary = call(3, 'hydrate')
local snapshot, sent = State.snapshot(), syncs[#syncs].payload
do
    check(ordinary.businesses[1].modules[1].webhook == nil, 'ordinary hydrate excludes webhook')
    check(snapshot[1].modules[1].webhook == nil and sent[1].modules[1].webhook == nil, 'default snapshot and broadcast exclude webhook')
    snapshot[1].modules[1].label = 'Public copy mutation'
    check(State.get('shop').modules[1].label == 'Till' and State.get('shop').modules[1].webhook == secret, 'public redaction/copy cannot alter authority')
end
check(registered.getBusiness('shop').modules[1].webhook == secret, 'trusted server single getter retains detached full definition')
check(registered.getBusinesses()[1].modules[1].webhook == secret, 'trusted server list getter retains existing full-definition contract')
local trusted = registered.getBusiness('shop')
trusted.modules[1].webhook = replacement
check(State.get('shop').modules[1].webhook == secret and registered.getBusiness('unknown') == nil,
    'trusted single getter stays detached and retains unknown-id behavior')
do
    check(State.snapshot(true)[1].modules[1].webhook == secret, 'explicit trusted snapshot retains webhook')
    check(State.snapshot('true')[1].modules[1].webhook == nil and State.snapshot(1)[1].modules[1].webhook == nil,
        'private inclusion requires literal true')
    check(call(3, 'hydrate', true).businesses[1].modules[1].webhook == nil, 'client extra argument cannot enable private hydrate')
end

local client = {}; for name, value in pairs(_G) do client[name] = value end
client.Config, client.json = server.Config, codec
local app, dialog, dialogAction, notifications = nil, nil, 'label', {}
local dialogCount = 0
client.GetCurrentResourceName = server.GetCurrentResourceName
client.GetGameTimer = function() return 1000 end
client.RegisterCommand, client.Wait, client.AddEventHandler = noop, noop, noop
client.RegisterNetEvent = function(name, handler) clientHandlers[name] = handler end
client.TriggerServerEvent = noop
client.CreateThread = function(callback) callback() end
client.Kora = {
    blips = server.Kora.blips, shared = server.Kora.shared,
    callback = { trigger = function(name, ...) return assert(callbacks[name], 'missing callback ' .. name).handler(currentClient, ...) end },
    notify = { send = function(value) notifications[#notifications + 1] = value end },
    nui = { isAppOpen = function() return false end, registerApp = function(value) app = value end, openApp = noop,
        openInputDialog = function(fields)
            dialogCount = dialogCount + 1
            dialog = codec.decode(fields[1].default)
            local edited = copy(dialog)
            if dialogAction == 'label' then edited.label = 'Edited label'
            elseif dialogAction == 'clear' then edited.webhook = nil
            elseif dialogAction == 'replace' then edited.webhook = replacement end
            return { values = { data = codec.encode(edited) } }
        end,
    },
}
client.exports = setmetatable({ kora_core = { getPlayerData = function() return players[currentClient].job end } },
    { __call = function(_, name, handler) registered['client:' .. name] = handler end })
client.KoraJobCreator = { schema = server.KoraJobCreator.schema, Business = { create = function() return {} end, destroy = noop } }
load('client/state.lua', client); load(resource .. '/client/creator.lua', client); load('client/main.lua', client)
local publicClient = registered['client:getBusinesses']().shop
check(publicClient.modules[1].webhook == nil, 'actual client cache/export matches public hydrate')
do
    local private = callbacks['kora_jobcreator:server:module']
    check(private and private.options.rateLimit, 'private edit read is explicitly rate-limited')
    check(call(3, 'module', 'shop', 1) == nil, 'ordinary caller cannot read module secret')
    check(call(2, 'module', 'shop', 1) == nil, 'business boss without creator permission cannot read module secret')
    check(call(1, 'module', 'missing', 1) == nil and call(1, 'module', 'shop', 99) == nil, 'private read rejects missing business/module')
    State.ready = false
    check(call(1, 'module', 'shop', 1) == nil, 'private read rejects before readiness')
    State.ready = true
    local privateModule = call(1, 'module', 'shop', 1)
    check(privateModule.webhook == secret, 'authorized creator reads complete module')
    privateModule.webhook = replacement
    check(State.get('shop').modules[1].webhook == secret, 'private module read stays detached')
end
currentClient = 1
client.KoraJobCreator.creator.setAdmin(true)
client.KoraJobCreator.creator.open()
check(app and type(app.onAction) == 'function', 'actual management console opens')
app.onAction('businesses:select', { itemId = 'shop' })
app.onAction('businesses:edit-module-data', { itemId = '1' })
check(dialog and dialog.webhook == secret, 'authorized JSON editor retains existing webhook in default data')
check(State.get('shop').modules[1].label == 'Edited label' and State.get('shop').modules[1].webhook == secret
    and persisted.shop[1].webhook == secret, 'unrelated authorized JSON edit preserves webhook and persists changed label')
check(registered['client:getBusinesses']().shop.modules[1].webhook == nil, 'private editor module never enters public client cache')
dialogAction = 'clear'
app.onAction('businesses:edit-module-data', { itemId = '1' })
check(State.get('shop').modules[1].webhook == nil and persisted.shop[1].webhook == nil, 'authorized explicit clear keeps existing absent-field semantics')
dialogAction = 'replace'
app.onAction('businesses:edit-module-data', { itemId = '1' })
check(State.get('shop').modules[1].webhook == replacement and persisted.shop[1].webhook == replacement,
    'authorized creator can set new webhook after clear')
check(registered['client:getBusinesses']().shop.modules[1].webhook == nil, 'changed webhook remains excluded from sync/cache/export')
local staleBusiness = copy(registered['client:getBusinesses']().shop)
local beforeDialogs, beforeNotifications = dialogCount, #notifications
adminAllowed = false
app.onAction('businesses:edit-module-data', { itemId = '1' })
check(dialogCount == beforeDialogs and #notifications > beforeNotifications and notifications[#notifications].type == 'error',
    'revoked creator permission prevents dialog and notifies')
check(State.get('shop').modules[1].webhook == replacement and persisted.shop[1].webhook == replacement,
    'denied editor cannot change saved webhook')
adminAllowed = true
check(call(1, 'removeModule', 'shop', 1), 'authorized actual module removal succeeds')
client.KoraJobCreator.client.definitions.shop = copy(staleBusiness)
beforeDialogs, beforeNotifications = dialogCount, #notifications
app.onAction('businesses:edit-module-data', { itemId = '1' })
check(dialogCount == beforeDialogs and #notifications > beforeNotifications and notifications[#notifications].type == 'error',
    'stale cached module deletion prevents dialog and notifies')
check(#State.get('shop').modules == 0 and #persisted.shop == 0, 'stale editor cannot revive removed module')
check(call(1, 'deleteBusiness', 'shop'), 'authorized actual business deletion succeeds')
client.KoraJobCreator.client.definitions.shop = copy(staleBusiness)
beforeDialogs, beforeNotifications = dialogCount, #notifications
app.onAction('businesses:edit-module-data', { itemId = '1' })
check(dialogCount == beforeDialogs and #notifications > beforeNotifications and notifications[#notifications].type == 'error',
    'deleted business with stale client cache prevents dialog and notifies')
check(State.get('shop') == nil and persisted.shop == nil and registered.getBusiness('shop') == nil,
    'stale editor cannot revive deleted business')

H.finish('webhook_privacy')
