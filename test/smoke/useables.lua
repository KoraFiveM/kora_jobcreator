-- Actual state/admin edits and inventory use dispatch, with inert host and SQL boundaries.
local H = dofile('test/harness.lua')
local check = H.ok
local source = arg[1] or 'server'
local function noop() end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local env = {}; for name, value in pairs(_G) do env[name] = value end
local handlers, callbacks, native, logs, notify, registrations = {}, {}, {}, {}, {}, {}
local counts = { box = 20, box2 = 20, ingredient = 20 }
local definitions = {}
for _, name in ipairs({ 'box', 'box2', 'old_reward', 'new_reward', 'other_reward', 'ingredient', 'recipe_old', 'recipe_new' }) do
    definitions[name] = { name = name, label = name, weight = 1, type = 'item' }
end
local player = { citizenid = 'CID7', name = 'Player 7', items = {}, job = { name = 'shop', onduty = true } }
local function rebuildItems()
    player.items = {}; local slot = 0
    for _, name in ipairs({ 'box', 'box2', 'old_reward', 'new_reward', 'other_reward', 'ingredient', 'recipe_old', 'recipe_new' }) do
        if (counts[name] or 0) > 0 then slot = slot + 1; player.items[slot] = { name = name, amount = counts[name], slot = slot, info = {} } end
    end
end
rebuildItems()
local core = {
    getShared = function(_, _, name) return definitions[name] end,
    allShared = function() return {} end,
    getPlayerData = function(_, _, path) return path and player.items or player end,
    hasPermission = function() return true end,
    getItemCount = function(_, _, name) return counts[name] or 0 end,
    canCarry = function() return true end,
    removeItem = function(_, _, name, amount)
        if (counts[name] or 0) < amount then return false end
        counts[name] = counts[name] - amount; rebuildItems(); return true
    end,
    addItem = function(_, _, name, amount) counts[name] = (counts[name] or 0) + amount; rebuildItems(); return true end,
}
env.GetCurrentResourceName = function() return 'kora_inventory' end
env.GetInvokingResource = function() return 'kora_jobcreator' end
env.GetGameTimer = function() return 1000 end
env.GetPlayerRoutingBucket = function() return 0 end
env.CreateThread, env.Wait, env.RegisterCommand = noop, noop, noop
env.AddEventHandler = function(name, callback) handlers[name] = handlers[name] or {}; handlers[name][#handlers[name] + 1] = callback end
env.RegisterNetEvent = env.AddEventHandler
env.TriggerClientEvent, env.TriggerEvent = noop, noop
env.QB = {
    resources = {}, compat = { isCallable = function(value) return type(value) == 'function' end },
    callback = { register = noop }, sql = {},
}
-- Cfx's exports boundary requires table resource access and callable registration.
env.exports = setmetatable({ kora_core = core }, { __call = function(_, name, fn) native[name] = fn end })
local function load(path, target) assert(loadfile(path, 't', target or env))() end
load('../kora_lib/local/resources/server.lua')
load('../kora_inventory/config.lua'); load('../kora_inventory/shared.lua'); load('../kora_inventory/server.lua')
load('../kora_inventory/server/crafting.lua')
local inventory = env.QbInventory
local job = {}; for name, value in pairs(env) do job[name] = value end
job.GetCurrentResourceName = function() return 'kora_jobcreator' end
job.QbJobCreator = {
    logs = { record = function(business, entry) logs[#logs + 1] = { business = business, entry = entry } end, recent = noop },
    pos = { register = noop, resetBusiness = noop },
    staff = { counts = function() return {} end },
}
local encoded, serial, failWrite = {}, 0, false
job.json = {
    encode = function(value) serial = serial + 1; local token = tostring(serial); encoded[token] = copy(value); return token end,
    decode = function(token) return copy(encoded[token]) end,
}
job.QB = {
    blips = { getCategoryIds = function() return {} end },
    util = { fnv1a = function() return 'test-revision' end },
    sql = { execute = function() if failWrite then return nil, 'controlled failure' end; return true end },
    shared = { get = function() return { name = 'shop', grades = {} } end, all = function() return {} end },
    callback = { register = function(name, callback) callbacks[name] = callback end },
    notify = { send = function(src, payload) notify[#notify + 1] = { src = src, payload = payload } end },
    rewards = { generate = function(pool, options)
        local result = {}; for _ = 1, options.rolls do result[#result + 1] = copy(pool[1]) end; return result
    end },
}
job.QB.sql.transaction = function() return not failWrite end
local inventoryExports = {}
for name, fn in pairs(native) do inventoryExports[name] = function(_, ...) return fn(...) end end
local create = inventoryExports.createUseable
inventoryExports.createUseable = function(_, name, callback)
    registrations[name] = (registrations[name] or 0) + 1; return create(nil, name, callback)
end
job.exports = setmetatable({ kora_core = core, kora_inventory = inventoryExports }, { __call = noop })
load('config.lua', job); load('shared/schema.lua', job)
job.Config.recipes.first = { ingredients = { { item = 'ingredient', amount = 2 } },
    give = { { item = 'recipe_old', amount = 1 } }, completeLabel = 'First crafted' }
job.Config.recipes.second = { ingredients = { { item = 'ingredient', amount = 3 } },
    give = { { item = 'recipe_new', amount = 2 } }, completeLabel = 'Second crafted' }
for _, name in ipairs({ 'state', 'crafting', 'register', 'admin' }) do load(source .. '/' .. name .. '.lua', job) end
local State, Crafting = job.QbJobCreator.state, job.QbJobCreator.crafting
State.ready = true
local function call(name, ...) return callbacks['qbjobcreator:server:' .. name](7, ...) end
local function module(item, reward, consume, rolls)
    return { moduleType = 'UseableItem', item = item, consume = consume or 1, useType = 'reward',
        rewards = { { item = reward, amount = 1, chance = 1 } }, rolls = rolls or 1 }
end
local function use(name) return inventory.api.useItem(7, name) end
check(call('createBusiness', { id = 'a', label = 'Original A', job = 'shop' }) == 'a', 'actual admin creates business')
check(call('saveModule', 'a', nil, module('box', 'old_reward')), 'actual admin creates useable module')
check(use('box'), 'native use dispatch executes initial registered callback')
check(counts.old_reward == 1 and counts.box == 19, 'initial definition consumes and grants once')
check(call('saveModule', 'a', 1, module('box', 'new_reward', 2, 2)), 'actual admin edits same item definition')
check(use('box'), 'native dispatch runs after edit')
check(counts.new_reward == 2 and counts.old_reward == 1 and counts.box == 17, 'edited definition updates consumption/rewards/rolls')
check(registrations.box == 1, 'same-item edit reuses one global handler')
check(call('editBusiness', 'a', { label = 'Renamed A' }), 'actual business edit succeeds')
check(use('box') and logs[#logs].business.label == 'Renamed A', 'current business metadata reaches use logs')
check(call('saveModule', 'a', 1, { moduleType = 'UseableItem', item = 'box', consume = 1, useType = 'recipe', recipe = 'first' }),
    'actual admin switches reward item to first recipe')
local boxBefore, ingredientBefore, rewardsBefore = counts.box, counts.ingredient, counts.new_reward
check(use('box') and counts.box == boxBefore - 1 and counts.ingredient == ingredientBefore - 2 and counts.recipe_old == 1,
    'first recipe uses current consume/ingredients/output through actual capacity query')
check(counts.new_reward == rewardsBefore and notify[#notify].payload.message == 'First crafted', 'reward-to-recipe switch uses recipe outcome')
check(call('saveModule', 'a', 1, { moduleType = 'UseableItem', item = 'box', consume = 3, useType = 'recipe', recipe = 'second' }),
    'actual admin edits current recipe reference and consume')
boxBefore, ingredientBefore = counts.box, counts.ingredient
check(use('box') and counts.box == boxBefore - 3 and counts.ingredient == ingredientBefore - 3
    and counts.recipe_new == 2 and counts.recipe_old == 1, 'recipe edit replaces prior recipe and consumption')
check(notify[#notify].payload.message == 'Second crafted' and logs[#logs].business.label == 'Renamed A',
    'current recipe outcome and business metadata reach notification/log')
check(registrations.box == 1, 'reward/recipe edits retain stable handler')
check(call('saveModule', 'a', 1, module('box', 'new_reward', 2, 2)), 'actual admin switches recipe back to reward')

failWrite = true
check(call('saveModule', 'a', 1, module('box', 'other_reward')) == false, 'failed persistence rejects edit')
failWrite = false
local before = counts.new_reward
check(use('box') and counts.new_reward == before + 2 and not counts.other_reward, 'failed edit leaves live binding unchanged')
check(call('createBusiness', { id = 'b', label = 'Business B', job = 'shop' }) == 'b', 'second business exists')
check(call('saveModule', 'b', nil, module('box', 'other_reward')), 'duplicate definition can persist as before')
before = counts.new_reward
check(use('box') and counts.new_reward == before + 2 and not counts.other_reward, 'active duplicate remains refused')
check(call('removeModule', 'b', 1), 'remove refused duplicate module')
before = counts.new_reward
check(use('box') and counts.new_reward == before + 2, 'removing another business preserves current owner')
check(call('saveModule', 'a', 1, module('box2', 'other_reward')), 'edit item name succeeds')
local oldCount, oldReward, notificationCount, logCount = counts.box, counts.new_reward, #notify, #logs
check(use('box') == false, 'renamed item old handler becomes inactive')
check(counts.box == oldCount and counts.new_reward == oldReward and #notify == notificationCount and #logs == logCount,
    'inactive handler consumes/grants/notifies/logs nothing')
check(use('box2') and counts.other_reward == 1, 'new item is registered and works')
check(call('removeModule', 'a', 1), 'remove module succeeds')
local box2Before, rewardBefore = counts.box2, counts.other_reward
check(use('box2') == false and counts.box2 == box2Before and counts.other_reward == rewardBefore, 'deleted module becomes inert')
check(call('saveModule', 'b', nil, module('box2', 'old_reward')), 'other business can now bind inactive item')
check(use('box2') and counts.old_reward == 2, 'reassigned item resolves new business/module')
check(registrations.box2 == 1, 'reassignment preserves stable global handler')
failWrite = true
check(call('deleteBusiness', 'b') == false, 'failed delete rejects before removing live binding')
failWrite = false
box2Before, rewardBefore = counts.box2, counts.old_reward
check(State.get('b') and use('box2') and counts.box2 == box2Before - 1 and counts.old_reward == rewardBefore + 1,
    'failed delete retains current business and item behavior')

check(call('deleteBusiness', 'b'), 'delete business succeeds')
box2Before, rewardBefore = counts.box2, counts.old_reward
check(use('box2') == false and counts.box2 == box2Before and counts.old_reward == rewardBefore, 'deleted business becomes inert')
Crafting.registerUseable({ id = 'direct', label = 'Direct helper' }, module('box', 'other_reward', 0))
rewardBefore = counts.other_reward
check(use('box') and counts.other_reward == rewardBefore + 1, 'direct two-argument helper remains compatible')
for _, callback in ipairs(handlers.onResourceStop or {}) do callback('kora_jobcreator') end
rewardBefore = counts.other_reward
check(use('box') == false and counts.other_reward == rewardBefore, 'existing provider owner-stop cleanup still applies')
H.finish('useables')
