-- Business recipes.
--
-- Shared `Config.recipes` are a file-backed library every business can point
-- at. Business recipes are the in-game half: an admin creates them from the
-- console, they are stored in SQL against ONE business, and only that business's
-- crafters and useable items can reference them. A business recipe shadows a
-- shared recipe with the same id inside its own business.
--
-- The client never supplies a recipe to craft. It supplies ids; this file is the
-- lookup the server performs with them.

KoraJobCreator = KoraJobCreator or {}

local S = KoraJobCreator.schema
local State = KoraJobCreator.state
local Logs = KoraJobCreator.logs

local Recipes = {}
KoraJobCreator.recipes = Recipes

---@type table<string, table<string, table>> businessId -> recipeId -> recipe
local cache = {}

local function copy(value) return json.decode(json.encode(value)) end

---@return boolean ok, string|nil err
function Recipes.load()
    local rows, err = Kora.sql.query('SELECT `business`, `id`, `data` FROM `kora_jobcreator_business_recipes`')
    if err then return false, err end
    cache = {}
    for _, row in ipairs(rows or {}) do
        local ok, decoded = pcall(json.decode, row.data or '')
        local recipe, recipeErr = S.normaliseRecipe(ok and decoded or nil)
        if recipe then
            cache[row.business] = cache[row.business] or {}
            cache[row.business][row.id] = recipe
        else
            Kora.logging.warn('recipes.rejected', 'Skipped a business recipe that failed validation', {
                businessId = tostring(row.business), recipeId = tostring(row.id), error = tostring(recipeErr) })
        end
    end
    return true
end

---Resolves a recipe id for a business: its own SQL recipe first, then the
---shared library.
---@param businessId? string
---@param id any
---@return table|nil recipe, boolean isBusinessRecipe
function Recipes.get(businessId, id)
    if type(id) == 'number' then id = tostring(math.floor(id)) end
    if type(id) ~= 'string' then return nil, false end
    local own = businessId and cache[businessId] and cache[businessId][id]
    if own then return own, true end
    local shared = Config.recipes[id]
    return type(shared) == 'table' and shared or nil, false
end

---@param businessId string
---@return table[] recipes sorted by label, each carrying its `id`
function Recipes.list(businessId)
    local list = {}
    for id, recipe in pairs(cache[businessId] or {}) do
        local entry = copy(recipe)
        entry.id = id
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    return list
end

---@return table[] shared recipe ids and labels
function Recipes.shared()
    local list = {}
    for id, recipe in pairs(Config.recipes) do
        if type(recipe) == 'table' then list[#list + 1] = { id = id, label = recipe.label or id } end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    return list
end

---Every place in a business that references a recipe id.
---@param business table
---@param id string
---@return string[] usages
function Recipes.usages(business, id)
    local found = {}
    for _, module in ipairs(business.modules or {}) do
        if module.moduleType == 'Crafting' then
            for _, ref in ipairs(module.recipes or {}) do
                if ref == id then found[#found + 1] = module.label end
            end
            for _, category in ipairs(module.crafters or {}) do
                for _, ref in ipairs(category.recipes or {}) do
                    if ref == id then found[#found + 1] = ('%s / %s'):format(module.label, category.label) end
                end
            end
        elseif module.moduleType == 'UseableItem' and module.recipe == id then
            found[#found + 1] = ('useable %s'):format(module.item)
        end
    end
    return found
end

local itemsCache
---@param name string
---@return boolean
local function knownItem(name)
    if not itemsCache then
        local ok, items = pcall(function() return exports.kora_core:getShared('items') end)
        itemsCache = ok and type(items) == 'table' and items or false
    end
    -- Without an item registry to ask, the inventory itself rejects unknown
    -- items at craft time; refusing every recipe here would be worse.
    if not itemsCache then return true end
    return itemsCache[name] ~= nil
end

---@param recipe table
---@return string|nil err
local function unknownItems(recipe)
    itemsCache = nil
    for _, field in ipairs({ 'ingredients', 'give' }) do
        for _, entry in ipairs(recipe[field]) do
            if not knownItem(entry.item) then return ('"%s" is not a registered item.'):format(entry.item) end
        end
    end
end

---@param businessId string
---@param label string
---@return string|nil id
local function newId(businessId, label)
    local base = S.slug(label)
    if not base then return nil end
    base = base:sub(1, 56)
    local id, suffix = base, 2
    local existing = cache[businessId] or {}
    while existing[id] do
        id = ('%s_%d'):format(base, suffix)
        suffix = suffix + 1
    end
    return id
end

---@param business table
---@param id? string nil to create
---@param raw any
---@return string|nil id, string|nil err
function Recipes.save(business, id, raw)
    local recipe, err = S.normaliseRecipe(raw)
    if not recipe then return nil, err end
    local unknown = unknownItems(recipe)
    if unknown then return nil, unknown end

    if id ~= nil then
        id = type(id) == 'string' and id or nil
        if not id or not (cache[business.id] and cache[business.id][id]) then return nil, 'That recipe no longer exists.' end
    else
        id = newId(business.id, recipe.label)
        if not id then return nil, 'That name cannot be used as a recipe id.' end
    end

    local _, writeErr = Kora.sql.execute([[INSERT INTO `kora_jobcreator_business_recipes` (`business`,`id`,`data`) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)]], { business.id, id, json.encode(recipe) })
    if writeErr then return nil, 'Could not save the recipe.' end

    cache[business.id] = cache[business.id] or {}
    cache[business.id][id] = recipe
    return id
end

---@param business table
---@param id any
---@return boolean ok, string|nil err
function Recipes.delete(business, id)
    if type(id) ~= 'string' or not (cache[business.id] and cache[business.id][id]) then
        return false, 'That recipe no longer exists.'
    end
    local usages = Recipes.usages(business, id)
    -- A shared recipe with the same id would silently take over the reference,
    -- which is still a different recipe than the one the admin is deleting.
    if #usages > 0 then
        return false, ('That recipe is still used by %s.'):format(table.concat(usages, ', '))
    end
    local _, writeErr = Kora.sql.execute('DELETE FROM `kora_jobcreator_business_recipes` WHERE `business` = ? AND `id` = ?', { business.id, id })
    if writeErr then return false, 'Could not delete the recipe.' end
    cache[business.id][id] = nil
    return true
end

---Deleting a business takes its private recipe library with it.
---@param businessId string
function Recipes.removeBusiness(businessId)
    cache[businessId] = nil
    local _, err = Kora.sql.execute('DELETE FROM `kora_jobcreator_business_recipes` WHERE `business` = ?', { businessId })
    if err then
        Kora.logging.warn('recipes.cleanup_failed', 'Could not delete recipes of a deleted business', {
            businessId = businessId, error = tostring(err) })
    end
end

---Resolves which recipe ids and which boundary a crafter category uses.
---A category id of nil or `default` on a single-anchor bench means the bench
---itself.
---@param module table
---@param categoryId any
---@return string[]|nil recipes, table|nil boundary, table|nil category
function Recipes.category(module, categoryId)
    if module.crafters then
        for _, category in ipairs(module.crafters) do
            if category.id == categoryId then
                -- Locations are sphere targets whose radius is the interaction
                -- distance, so the reachable boundary is twice it (as
                -- State.moduleBoundary does for a sphere zone).
                return category.recipes, { coords = category.locations, distance = module.distance * 2 }, category
            end
        end
        return nil
    end
    if categoryId ~= nil and categoryId ~= 'default' then return nil end
    return module.recipes, module, { id = 'default', label = module.label, recipes = module.recipes }
end

---@param business table
---@param ids string[]
---@return table[] recipes in category order, ready for the client menu
local function present(business, ids)
    local list = {}
    for _, id in ipairs(ids or {}) do
        local recipe = Recipes.get(business.id, id)
        if recipe then
            local entry = copy(recipe)
            entry.id = id
            entry.output = entry.give and entry.give[1] or nil
            list[#list + 1] = entry
        end
    end
    return list
end

---@param src integer
---@param businessId any
---@return table|nil business, string|nil err
local function adminBusiness(src, businessId)
    if not State.ready then return nil, 'Businesses are still loading.' end
    if not State.isAdmin(src) then return nil, 'You cannot edit businesses.' end
    local business = State.get(businessId)
    if not business then return nil, 'Unknown business.' end
    return business
end

Kora.callback.register('kora_jobcreator:server:recipes', function(src, businessId)
    local business, err = adminBusiness(src, businessId)
    if not business then return nil, err end
    local list = Recipes.list(business.id)
    for _, recipe in ipairs(list) do recipe.usages = Recipes.usages(business, recipe.id) end
    return { business = list, shared = Recipes.shared() }
end, { rateLimit = { max = 10, window = 10000 } })

Kora.callback.register('kora_jobcreator:server:saveRecipe', function(src, businessId, id, payload)
    local business, err = adminBusiness(src, businessId)
    if not business then return nil, err end
    local saved, saveErr = Recipes.save(business, id, payload)
    if not saved then return nil, saveErr end
    Logs.record(business, {
        category = 'admin', src = src,
        message = ('%s recipe "%s".'):format(id and 'Updated' or 'Created', tostring(payload and payload.label or saved)),
    })
    return saved
end, { rateLimit = { max = 20, window = 30000 } })

Kora.callback.register('kora_jobcreator:server:deleteRecipe', function(src, businessId, id)
    local business, err = adminBusiness(src, businessId)
    if not business then return false, err end
    local recipe = type(id) == 'string' and Recipes.get(business.id, id) or nil
    local ok, deleteErr = Recipes.delete(business, id)
    if not ok then return false, deleteErr end
    Logs.record(business, { category = 'admin', src = src, message = ('Deleted recipe "%s".'):format(recipe and recipe.label or tostring(id)) })
    return true
end, { rateLimit = { max = 10, window = 30000 } })

---The recipes one crafter category offers, resolved server-side so a client
---only ever renders what it could actually craft there.
Kora.callback.register('kora_jobcreator:server:benchRecipes', function(src, businessId, moduleIndex, categoryId)
    local business = State.get(businessId)
    if not business then return nil, 'Unknown business.' end
    local module = State.module(business, moduleIndex)
    if not module or module.moduleType ~= 'Crafting' then return nil, 'Unknown crafting station.' end
    if not State.worksFor(src, business.job) then return nil, 'You do not work here.' end
    local ids = Recipes.category(module, categoryId)
    if not ids then return nil, 'Unknown crafting station.' end
    return present(business, ids)
end, { rateLimit = { max = 20, window = 10000 } })
