-- Employee pickup stores.
--
-- A store category is a priced ingredient list placed at one or more points in
-- the business. Staff open it, pick an item and a quantity, and receive it.
-- Supply is unlimited: there is no kora_inventory shop and no stock count, so
-- nothing here can drift out of sync with an inventory.
--
-- The client supplies intent only -- business, category, item name, quantity.
-- The price, the item list and the payer all come from the saved definition.

KoraJobCreator = KoraJobCreator or {}

local State = KoraJobCreator.state
local Logs = KoraJobCreator.logs
local Pos = KoraJobCreator.pos

local Stores = {}
KoraJobCreator.stores = Stores

---@type table<integer, true> players with a pickup in flight
local busy = {}

AddEventHandler('playerDropped', function() busy[source] = nil end)

---@param business table
---@return table|nil module the business's Sales Items module
function Stores.salesModule(business)
    for _, module in ipairs(business and business.modules or {}) do
        if module.moduleType == 'SalesItems' then return module end
    end
end

---@param src integer
---@param businessId any
---@param categoryId any
---@return table|nil business, table|nil category, string|nil err
local function storeContext(src, businessId, categoryId)
    local business = State.get(businessId)
    if not business then return nil, nil, 'Unknown business.' end
    local job = State.playerJob(src)
    if not job or job.name ~= business.job then return nil, nil, 'You do not work here.' end

    local module = Stores.salesModule(business)
    local category
    for _, entry in ipairs(module and module.stores or {}) do
        if entry.id == categoryId then category = entry; break end
    end
    if not category then return nil, nil, 'This store no longer exists.' end

    -- Store points are sphere targets whose radius is the interaction distance.
    if not State.nearModule(src, { coords = category.locations, distance = (module.distance or 2.0) * 2 }) then
        return nil, nil, 'You are too far away.'
    end
    return business, category
end

local function itemLabels()
    local ok, items = pcall(function() return exports.kora_core:getShared('items') end)
    return ok and type(items) == 'table' and items or {}
end

Kora.callback.register('kora_jobcreator:server:storeCatalog', function(src, businessId, categoryId)
    local _, category, err = storeContext(src, businessId, categoryId)
    if not category then return nil, err end
    local shared, items = itemLabels(), {}
    for _, entry in ipairs(category.items) do
        local definition = shared[entry.item]
        items[#items + 1] = {
            name = entry.item, price = entry.price,
            label = type(definition) == 'table' and definition.label or entry.item,
        }
    end
    return { id = category.id, label = category.label, payFrom = category.payFrom, items = items }
end, { rateLimit = { max = 10, window = 10000 } })

---@param src integer
---@param business table
---@param category table
---@param itemName any
---@param amount any
---@return boolean ok, string|nil message
function Stores.purchase(src, business, category, itemName, amount)
    local name = type(itemName) == 'string' and itemName:lower() or nil
    local entry
    for _, candidate in ipairs(category.items) do
        if candidate.item == name then entry = candidate; break end
    end
    if not entry then return false, 'That item is not sold here.' end

    amount = tonumber(amount)
    if not amount or amount ~= amount or amount % 1 ~= 0 or amount < 1 or amount > Config.stores.maxQuantity then
        return false, ('Choose a quantity between 1 and %d.'):format(Config.stores.maxQuantity)
    end
    local total = entry.price * amount
    if not exports.kora_core:canCarry(src, entry.item, amount) then return false, 'You cannot carry that much.' end

    if category.payFrom == 'business' then
        local debited, debitErr = Pos.debit(business.job, total, 'store pickup')
        if not debited then return false, debitErr or 'The business cannot afford that.' end
        local added = exports.kora_core:addItem(src, entry.item, amount)
        if not added then
            Pos.credit(business.job, total, 'store pickup refund')
            return false, 'You cannot carry that much.'
        end
    else
        local definition = {
            reason = 'kora_jobcreator-store-pickup',
            items = { add = { { item = entry.item, amount = amount } } },
        }
        if total > 0 then definition.money = { remove = { { account = Config.stores.account, amount = total } } } end
        local called, ok, err = pcall(function() return exports.kora_core:transaction(src, definition) end)
        if not called then return false, 'The store is unavailable.' end
        if not ok then return false, err or 'You cannot afford that.' end
    end

    Logs.record(business, {
        category = 'stock', src = src, amount = total,
        message = ('Picked up %dx %s from %s for $%d (%s).'):format(amount, entry.item, category.label, total,
            category.payFrom == 'business' and 'business account' or 'employee'),
    })
    return true, ('Picked up %dx %s for $%d.'):format(amount, entry.item, total)
end

Kora.callback.register('kora_jobcreator:server:purchaseStoreItem', function(src, businessId, categoryId, itemName, amount)
    if busy[src] then return false, 'Your last pickup is still processing.' end
    local business, category, err = storeContext(src, businessId, categoryId)
    if not category then return false, err end
    busy[src] = true
    local results = table.pack(pcall(Stores.purchase, src, business, category, itemName, amount))
    busy[src] = nil
    if not results[1] then
        Kora.logging.error('stores.purchase_failed', 'Store pickup failed unexpectedly', { error = tostring(results[2]) })
        return false, 'The pickup could not be completed.'
    end
    return table.unpack(results, 2, results.n)
end, { rateLimit = { max = 10, window = 10000 } })
