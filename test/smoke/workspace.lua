-- Business workspace flows, run for real against the server files with an inert
-- host: business recipes, category crafting, employee stores, sales items and
-- closed-shop gating. SQL, inventory and money are recorded, not performed.
local H = dofile('test/harness.lua')
local function noop() end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local encoded, serial = {}, 0
local codec = {
    encode = function(value) serial = serial + 1; local id = tostring(serial); encoded[id] = copy(value); return id end,
    decode = function(id) return copy(encoded[id]) end,
}

local env = {}; for name, value in pairs(_G) do env[name] = value end
local callbacks, transactions, debits, added, sqlWrites = {}, {}, {}, {}, {}
local positions = { [1] = { x = 0, y = 0, z = 0 }, [2] = { x = 0, y = 0, z = 0 }, [3] = { x = 0, y = 0, z = 0 } }
local players = {
    [1] = { citizenid = 'A', job = { name = 'police', grade = { level = 0 } } },
    [2] = { citizenid = 'B', job = { name = 'diner', grade = { level = 0 }, onduty = true } },
    [3] = { citizenid = 'C', job = { name = 'unemployed', grade = { level = 0 } } },
}
local items = { lettuce = { name = 'lettuce', label = 'Lettuce' }, salad = { name = 'salad', label = 'Salad' },
    bread = { name = 'bread', label = 'Bread' } }
local staffCount = 0

env.json = codec
env.GetCurrentResourceName = function() return 'kora_jobcreator' end
env.GetResourceState = function() return 'started' end
env.GetPlayerPed = function(src) return src end
local clientHandlers = {}
env.TriggerClientEvent = function(name, _, payload)
    if clientHandlers[name] then clientHandlers[name](copy(payload)) end
end
env.AddEventHandler, env.RegisterNetEvent = noop, noop
env.Kora = {
    util = {}, compat = {},
    blips = { getCategoryIds = function() return { Business = 1 } end },
    callback = { register = function(name, handler, options) callbacks[name] = { handler = handler, options = options } end,
        trigger = noop },
    shared = { get = function(kind, name)
        if kind == 'jobs' and name == 'diner' then return { name = 'diner', grades = { [0] = {} } } end
    end, all = function() return {} end },
    logging = { warn = noop, error = noop, info = noop },
    notify = { send = noop },
    sql = {
        execute = function(sql, params) sqlWrites[#sqlWrites + 1] = { sql = sql, params = params }; return true end,
        executeAsync = noop, query = function() return {} end,
    },
    distance = { player = function(src, point, distance)
        local at = positions[src]
        local x, y, z = at.x - point.x, at.y - point.y, at.z - point.z
        return math.sqrt(x * x + y * y + z * z) <= distance
    end },
}
env.exports = setmetatable({
    kora_core = {
        getPlayerData = function(_, src) return players[src] end,
        hasPermission = function(_, src) return src == 1 end,
        getShared = function() return items end,
        canCarry = function() return true end,
        getItemCount = function() return 10 end,
        removeItem = function() return true end,
        addItem = function(_, src, item, amount) added[#added + 1] = { src = src, item = item, amount = amount }; return true end,
        addMoney = function() return true end,
        transaction = function(_, src, definition) transactions[#transactions + 1] = { src = src, definition = copy(definition) }; return true end,
    },
    kora_inventory = setmetatable({ CanCraftItems = function() return true end }, { __index = function() return noop end }),
    kora_bossmenu = {
        removeBusinessMoney = function(_, job, amount) debits[#debits + 1] = { job = job, amount = amount }; return true end,
        addBusinessMoney = function() return true end,
        getBusinessBalance = function() return 100 end,
    },
}, { __call = noop })

local function load(path) assert(loadfile(path, 't', env))() end
load('../kora_lib/modules/util/shared.lua')
load('config.lua')
load('shared/schema.lua')
env.KoraJobCreator.register = { business = noop, removeBusiness = noop }
env.KoraJobCreator.logs = { record = noop, recent = function() return {} end }
env.KoraJobCreator.staff = { counts = function() return {} end, countFor = function() return staffCount end }
load('server/state.lua')
load('server/pos.lua')
load('server/recipes.lua')
load('server/crafting.lua')
load('server/stores.lua')
load('server/admin.lua')

local State = env.KoraJobCreator.state
local Pos = env.KoraJobCreator.pos
State.ready = true
local function call(src, name, ...)
    return assert(callbacks['kora_jobcreator:server:' .. name], 'missing callback ' .. name).handler(src, ...)
end
for name, entry in pairs(callbacks) do
    H.ok(entry.options and entry.options.rateLimit, name .. ' is rate limited')
end

local origin = { x = 0, y = 0, z = 0 }
H.ok(State.persist({ id = 'diner', label = 'Diner', job = 'diner', modules = {
    { moduleType = 'Zone', zoneType = 'sphere', coords = origin, radius = 30 },
    { moduleType = 'SalesItems', items = { 'salad' }, stores = {
        { label = 'Produce', items = { { item = 'lettuce', price = 3 } }, locations = { origin } },
        { label = 'Bakery', payFrom = 'business', items = { { item = 'bread', price = 4 } }, locations = { origin } },
    } },
    { moduleType = 'Crafting', label = 'Kitchen', crafters = {
        { label = 'Prep', recipes = {}, locations = { { x = 10, y = 0, z = 0 } } },
    } },
    { moduleType = 'POS', id = 'diner_till', zoneType = 'sphere', coords = origin },
    { moduleType = 'POS', id = 'diner_shop', closedShop = true, zoneType = 'sphere', coords = origin },
} }), 'a business with the new module shapes persists')

-- Recipes --------------------------------------------------------------------
H.equal(call(2, 'saveRecipe', 'diner', nil, { label = 'Salad', give = { { item = 'salad' } } }), nil,
    'an employee cannot create recipes')
local unknownId, unknownErr = call(1, 'saveRecipe', 'diner', nil, { label = 'Ghost', give = { { item = 'ghost' } } })
H.rejects(unknownId, unknownErr, 'a recipe output must be a registered item')
local saladId = call(1, 'saveRecipe', 'diner', nil, {
    label = 'Salad', time = 1000, ingredients = { { item = 'lettuce', amount = 2 } }, give = { { item = 'salad' } } })
H.equal(saladId, 'salad', 'an admin creates a business recipe')
H.equal(call(1, 'saveRecipe', 'diner', nil, { label = 'Salad', give = { { item = 'salad' } } }), 'salad_2',
    'a second recipe with the same name gets its own id')
H.ok(sqlWrites[#sqlWrites].sql:find('kora_jobcreator_business_recipes', 1, true), 'recipes are written to their own table')
H.equal(#call(1, 'recipes', 'diner').business, 2, 'the recipe list is per business')

-- Assign it through the normal module write path.
local kitchen = call(1, 'module', 'diner', 3)
kitchen.crafters[1].recipes = { 'salad' }
H.ok(call(1, 'saveModule', 'diner', 3, kitchen), 'a category recipe assignment saves')
local okDelete, deleteErr = call(1, 'deleteRecipe', 'diner', 'salad')
H.nope(okDelete, 'a recipe in use cannot be deleted')
H.ok(deleteErr:find('Kitchen / Prep', 1, true), 'the refusal names where it is used')
H.ok(call(1, 'deleteRecipe', 'diner', 'salad_2'), 'an unused recipe can be deleted')

-- Crafting ------------------------------------------------------------------
H.equal(call(3, 'benchRecipes', 'diner', 3, 'prep'), nil, 'an outsider cannot read bench recipes')
local bench = call(2, 'benchRecipes', 'diner', 3, 'prep')
H.equal(bench[1].id, 'salad', 'staff see the category recipes')
H.equal(bench[1].output.item, 'salad', 'the menu receives the output item for its image')
local okFar, farErr = call(2, 'craft', 'diner', 3, 'prep', 'salad')
H.nope(okFar, 'crafting away from every category location is refused')
H.equal(farErr, 'You are not at the bench.', 'the distance refusal is explained')
positions[2] = { x = 10, y = 0, z = 0.5 }
H.ok(call(2, 'craft', 'diner', 3, 'prep', 'salad'), 'crafting at a category location works')
H.equal(added[#added].item, 'salad', 'the craft produced the recipe output')
local okOther, otherErr = call(2, 'craft', 'diner', 3, 'prep', 'bs_burger')
H.nope(okOther, 'a recipe the category does not offer is refused')
H.equal(otherErr, 'That is not made here.', 'the offer refusal is explained')
H.nope(call(2, 'craft', 'diner', 3, 'missing', 'salad'), 'an unknown category is refused')
H.nope(call(3, 'craft', 'diner', 3, 'prep', 'salad'), 'an outsider cannot craft')

-- Stores --------------------------------------------------------------------
positions[2] = { x = 0, y = 0, z = 0 }
local catalog = call(2, 'storeCatalog', 'diner', 'produce')
H.equal(catalog.items[1].price, 3, 'the catalog carries the saved price')
H.equal(catalog.items[1].label, 'Lettuce', 'the catalog carries the item label')
H.equal(call(3, 'storeCatalog', 'diner', 'produce'), nil, 'an outsider cannot open a store')
H.ok(call(2, 'purchaseStoreItem', 'diner', 'produce', 'lettuce', 2), 'an employee picks up from a store')
local charge = transactions[#transactions].definition
H.equal(charge.money.remove[1].amount, 6, 'the employee is charged the saved price times quantity')
H.equal(charge.money.remove[1].account, Config and Config.stores.account or 'bank', 'the configured account is charged')
H.equal(charge.items.add[1].amount, 2, 'the items are granted in the same transaction')
H.ok(call(2, 'purchaseStoreItem', 'diner', 'bakery', 'bread', 1), 'a business-paid store works')
H.equal(debits[#debits].amount, 4, 'a business-paid store debits the business account')
H.nope(call(2, 'purchaseStoreItem', 'diner', 'produce', 'bread', 1), 'an item from another store is refused')
H.nope(call(2, 'purchaseStoreItem', 'diner', 'produce', 'lettuce', 0), 'a zero quantity is refused')
H.nope(call(2, 'purchaseStoreItem', 'diner', 'produce', 'lettuce', 1.5), 'a fractional quantity is refused')
positions[2] = { x = 50, y = 0, z = 0 }
H.nope(call(2, 'purchaseStoreItem', 'diner', 'produce', 'lettuce', 1), 'a pickup away from the store is refused')

-- Admin guards ----------------------------------------------------------------
local okDup, dupErr = call(1, 'saveModule', 'diner', nil, { moduleType = 'SalesItems', items = { 'salad' } })
H.nope(okDup, 'a second sales items module is refused')
H.ok(dupErr, 'the duplicate refusal is explained')
H.ok(State.persist({ id = 'stand', label = 'Stand', job = 'diner', modules = {} }), 'a business without a zone persists')
H.nope(call(1, 'saveModule', 'stand', nil, { moduleType = 'POS', id = 'stand_shop', closedShop = true,
    zoneType = 'sphere', coords = origin }), 'a closed shop needs a business zone')

-- Closed shops ---------------------------------------------------------------
local tillModule, shopModule = State.get('diner').modules[4], State.get('diner').modules[5]
Pos.register(State.get('diner'), tillModule)
Pos.register(State.get('diner'), shopModule)
H.nope(call(3, 'openShop', 'diner_till'), 'a staffed till has no customer shelf')
staffCount = 1
H.nope(call(3, 'openShop', 'diner_shop'), 'customers wait for staff while someone is working')
staffCount = 0
H.ok(Pos.accepts('diner_shop', 'salad'), 'a closed shop accepts the business sales items')
H.nope(Pos.accepts('diner_shop', 'lettuce'), 'a closed shop refuses items that are not sales items')

-- The real console: drive the new pages through the AppShell action handler,
-- with every callback answered by the real server files above.
local client = {}; for name, value in pairs(_G) do client[name] = value end
local app, notices = nil, {}
client.json, client.Config = codec, env.Config
client.GetCurrentResourceName = env.GetCurrentResourceName
client.RegisterCommand, client.Wait, client.AddEventHandler, client.TriggerServerEvent = noop, noop, noop, noop
client.RegisterNetEvent = function(name, handler) clientHandlers[name] = handler end
client.CreateThread = function(callback) callback() end
client.Kora = {
    blips = env.Kora.blips, logging = env.Kora.logging,
    shared = {
        get = function(kind, name) return kind == 'items' and items[name] or nil end,
        all = function(kind) local list = {}; if kind == 'items' then for _, item in pairs(items) do list[#list + 1] = item end end; return list end,
    },
    callback = { trigger = function(name, ...)
        return assert(callbacks[name], 'missing callback ' .. name).handler(1, ...)
    end },
    notify = { send = function(value) notices[#notices + 1] = value end },
    nui = { isAppOpen = function() return false end, registerApp = function(value) app = value end, openApp = noop,
        updateApp = noop },
}
client.exports = setmetatable({ kora_core = { getPlayerData = function() return players[1].job end } }, { __call = noop })
client.KoraJobCreator = { schema = env.KoraJobCreator.schema, Business = { create = function() return {} end, destroy = noop } }
local function loadClient(path) assert(loadfile(path, 't', client))() end
loadClient('client/state.lua'); loadClient('client/creator.lua'); loadClient('client/main.lua')
State.broadcast()
client.KoraJobCreator.creator.setAdmin(true)
client.KoraJobCreator.creator.open()
H.ok(app and app.onAction, 'the console opens')
local function act(actionId, itemId, value)
    local result = app.onAction(actionId, { itemId = itemId, value = value })
    if result and result.notice and result.notice.tone == 'destructive' then
        error(('%s failed: %s'):format(actionId, result.notice.message), 2)
    end
    for key, value in pairs(result and result.update or {}) do app[key] = value end
    return result
end
local function tab(id)
    for _, view in ipairs(app.navigation) do
        for _, entry in ipairs(view.tabs or {}) do if entry.id == id then return entry end end
    end
end
act('businesses:select', 'diner')
for _, id in ipairs({ 'tills', 'stashes', 'sales', 'stores', 'recipes', 'crafters' }) do
    H.ok(tab(id), ('the %s page is part of the admin workspace'):format(id))
end
local diner = function() return State.get('diner') end
local function sales() for _, module in ipairs(diner().modules) do if module.moduleType == 'SalesItems' then return module end end end

act('sales:add', nil, { items = { 'bread' } })
H.equal(#sales().items, 2, 'Sales Items: add')
act('sales:remove', 'bread')
H.equal(#sales().items, 1, 'Sales Items: remove')
act('stores:create', nil, { label = 'Dairy', payFrom = 'business' })
H.equal(sales().stores[3].id, 'dairy', 'Stores: create')
act('stores:add-item', 'dairy', { item = 'bread', price = 9 })
H.equal(sales().stores[3].items[1].price, 9, 'Stores: add item')
act('stores:price-item', 'dairy|bread', { price = 11 })
H.equal(sales().stores[3].items[1].price, 11, 'Stores: reprice')
act('stores:edit', 'dairy', { label = 'Dairy & Bread', payFrom = 'player' })
H.equal(sales().stores[3].payFrom, 'player', 'Stores: settings')
act('stores:remove-item', 'dairy|bread')
H.equal(#sales().stores[3].items, 0, 'Stores: remove item')
act('stores:delete', 'dairy')
H.equal(#sales().stores, 2, 'Stores: delete')

act('recipes:create', nil, { label = 'Toast', seconds = 2,
    ingredients = { { key = 'bread', value = '1' } }, give = { { key = 'salad', value = '2' } } })
local toast = env.KoraJobCreator.recipes.get('diner', 'toast')
H.ok(toast and toast.time == 2000 and toast.give[1].amount == 2, 'Recipes: create from the key-value form')
act('recipes:edit', 'toast', { label = 'Toast', seconds = 1, ingredients = {}, give = { { key = 'salad', value = '1' } } })
H.equal(env.KoraJobCreator.recipes.get('diner', 'toast').time, 1000, 'Recipes: edit')

act('crafters:create', nil, { label = 'Bar' })
local barIndex = #diner().modules
H.equal(diner().modules[barIndex].label, 'Bar', 'Crafters: create')
act('crafters:add-category', tostring(barIndex), { label = 'Drinks' })
act('crafters:recipes', barIndex .. '|drinks', { recipes = { 'toast', 'salad' } })
H.equal(#diner().modules[barIndex].crafters[1].recipes, 2, 'Crafters: assign recipes to a category')
act('crafters:rename-category', barIndex .. '|drinks', { label = 'Cocktails' })
H.equal(diner().modules[barIndex].crafters[1].label, 'Cocktails', 'Crafters: rename a category, keeping its id')
H.equal(diner().modules[barIndex].crafters[1].id, 'drinks', 'a renamed category keeps its id')
local refused = app.onAction('recipes:delete', { itemId = 'toast' })
H.equal(refused.notice.tone, 'destructive', 'Recipes: a recipe used by a category is not deleted')
H.ok(refused.notice.message:find('Bar / Cocktails', 1, true), 'the console says where the recipe is used')
act('crafters:delete-category', barIndex .. '|drinks')
H.equal(#diner().modules[barIndex].crafters, 0, 'Crafters: delete a category')
act('recipes:delete', 'toast')
H.equal(env.KoraJobCreator.recipes.get('diner', 'toast'), nil, 'Recipes: delete once unused')
act('crafters:delete', tostring(barIndex))
H.equal(#diner().modules, barIndex - 1, 'Crafters: delete')

act('tills:settings', '5', { label = 'Night shelf', closedShop = true, currency = 'bank', panicButton = true })
H.equal(diner().modules[5].label, 'Night shelf', 'Tills: settings')
H.equal(diner().modules[5].currency, 'bank', 'Tills: currency')
act('tills:settings', '4', { label = 'Front', closedShop = false, panicButton = true })
H.equal(diner().modules[4].panicButton, true, 'Tills: panic button on a staffed till')

H.finish('workspace')
