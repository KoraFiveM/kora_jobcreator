-- The in-game business builder.
--
-- Everything an admin builds here goes straight to the database and out to
-- every connected client: there is no file to write, no snippet to paste and no
-- restart. The dialogs collect a module, the server validates and stores it, and
-- the sync that comes back rebuilds the world.
--
-- World anchors are never typed in. Zones come from kora_lib's in-world zone
-- creator, props from its placement tool, and "use what is already there" from
-- a camera raycast -- so a till sits exactly where the counter is.

KoraJobCreator = KoraJobCreator or {}

local S = KoraJobCreator.schema
local Client = KoraJobCreator.client

local Creator = {}
KoraJobCreator.creator = Creator

local isAdmin = false

local function blipCategoryOptions()
    local names = {}
    for name in pairs(Kora.blips.getCategoryIds()) do names[#names + 1] = name end
    table.sort(names)

    local options = {}
    for _, name in ipairs(names) do options[#options + 1] = { value = name, label = name } end
    return options
end

---@param items table[]
---@param title string
---@return string|nil selectedId
local function pick(items, title)
    local result = Kora.nui.openMenu(items, title)
    if not result or result.cancelled then return nil end
    return result.selectedId
end

---@param fields table[]
---@param title string
---@param description? string
---@return table|nil values
local function form(fields, title, description)
    local result = Kora.nui.openInputDialog(fields, title, description)
    if not result or result.cancelled then return nil end
    return result.values
end

---Converts a `Kora.zones.startCreator` result into the flat fields the schema
---stores. The creator speaks in constructor options; the schema speaks in
---plain JSON, and this is the only place the two meet.
---@param result table
---@return table|nil
local function zoneFields(result)
    local opts, fields = result.opts, { zoneType = result.type }
    if result.type == 'sphere' then
        fields.coords = { x = opts.coords.x, y = opts.coords.y, z = opts.coords.z }
        fields.radius = opts.radius
    elseif result.type == 'box' then
        fields.coords = { x = opts.coords.x, y = opts.coords.y, z = opts.coords.z }
        fields.size = { x = opts.size.x, y = opts.size.y, z = opts.size.z }
        fields.rotation = opts.rotation or 0.0
    elseif result.type == 'poly' then
        local points = {}
        for _, point in ipairs(opts.points) do points[#points + 1] = { x = point.x, y = point.y, z = point.z } end
        fields.points = points
        fields.thickness = opts.thickness
        -- A poly has no single centre, so the first point doubles as the
        -- anchor a blip or a distance check needs.
        fields.coords = points[1]
    end
    return fields
end

---Aim at something already in the world and press E. What comes back is a box
---zone sized to that object's own model, because a map prop's model NAME is not
---recoverable from its hash at runtime -- only its dimensions are.
---@return table|nil
local function pickExisting()
    local prompt = Kora.textui.show('Look at the object and press ~b~E~s~ -- ~r~Backspace~s~ to cancel')
    local fields

    while true do
        Wait(0)
        local hit, coords, entity = Kora.raycast.fromCamera(25.0)
        if hit and entity and entity ~= 0 then
            DrawMarker(28, coords.x, coords.y, coords.z, 0, 0, 0, 0, 0, 0, 0.2, 0.2, 0.2, 0, 200, 120, 120, false, false, 2, nil, nil, false)
        end

        if IsControlJustReleased(0, 202) then break end

        if IsControlJustReleased(0, 38) and hit and entity and entity ~= 0 then
            local min, max = GetModelDimensions(GetEntityModel(entity))
            local position = GetEntityCoords(entity)
            fields = {
                zoneType = 'box',
                coords = { x = position.x, y = position.y, z = position.z + ((max.z - min.z) / 2) },
                size = { x = max.x - min.x, y = max.y - min.y, z = max.z - min.z },
                rotation = GetEntityHeading(entity),
            }
            break
        end
    end

    Kora.textui.hide(prompt)
    return fields
end

---@param modelType 'ped'|'object'|'vehicle'
---@return table|nil
local function pickEntity(modelType)
    local values = form({
        { id = 'model', label = 'Model name', type = 'text', required = true },
    }, ('Place a %s'):format(modelType))
    if not values then return nil end

    local model = tostring(values.model)
    if not IsModelValid(joaat(model)) then
        Client.notify(('"%s" is not a valid model.'):format(model), 'error')
        return nil
    end

    local placement = Kora.placement.start(model)
    if not placement then return nil end

    return {
        model = { model = model, modelType = modelType },
        coords = { {
            x = placement.coords.x, y = placement.coords.y, z = placement.coords.z,
            w = placement.heading or 0.0,
        } },
    }
end

---@param allowed 'zone'|'model'|'any'
---@return table|nil fields
local function pickAnchor(allowed)
    local choices = {}
    if allowed ~= 'model' then
        choices[#choices + 1] = { id = 'sphere', label = 'Sphere zone', description = 'A radius around a point' }
        choices[#choices + 1] = { id = 'box', label = 'Box zone', description = 'A rotatable box' }
        choices[#choices + 1] = { id = 'poly', label = 'Poly zone', description = 'A drawn footprint' }
        choices[#choices + 1] = { id = 'existing', label = 'An object already here', description = 'Aim at it and press E' }
    end
    if allowed ~= 'zone' then
        choices[#choices + 1] = { id = 'object', label = 'Place a prop', description = 'Spawn and position an object' }
        choices[#choices + 1] = { id = 'ped', label = 'Place a ped' }
        choices[#choices + 1] = { id = 'vehicle', label = 'Place a vehicle' }
    end

    local kind = pick(choices, 'Where is it?')
    if not kind then return nil end

    if kind == 'existing' then return pickExisting() end
    if kind == 'object' or kind == 'ped' or kind == 'vehicle' then return pickEntity(kind) end

    local result = Kora.zones.startCreator(kind)
    if not result then return nil end
    return zoneFields(result)
end

---@return table|nil
local function pickBlip()
    local values = form({
        { id = 'wanted', label = 'Add a map blip?', type = 'checkbox' },
    }, 'Map blip')
    if not values or not values.wanted then return nil end

    local blip = form({
        { id = 'category', label = 'Map category', type = 'select', required = true,
          default = 'Business', options = blipCategoryOptions() },
        { id = 'name', label = 'Location or storefront name', type = 'text' },
        { id = 'sprite', label = 'Sprite', type = 'number', default = 1, min = 0, max = 900 },
        { id = 'color', label = 'Colour', type = 'number', default = 1, min = 0, max = 90 },
        { id = 'scale', label = 'Scale', type = 'number', default = 0.7, min = 0.1, max = 3.0 },
    }, 'Map blip')
    if not blip then return nil end

    return {
        enabled = true, category = blip.category, name = blip.name, sprite = blip.sprite,
        color = blip.color, scale = blip.scale,
    }
end

---Business recipes first, then the shared library. Asked from the server
---because business recipes live in SQL, not in the replicated definition.
---@param business table
---@return table[] options `{ value, label }`
local function recipeOptions(business)
    local result = Kora.callback.trigger('kora_jobcreator:server:recipes', business.id)
    local options, seen = {}, {}
    for _, recipe in ipairs(type(result) == 'table' and result.business or {}) do
        seen[recipe.id] = true
        options[#options + 1] = { value = recipe.id, label = ('%s (business)'):format(recipe.label) }
    end
    for _, recipe in ipairs(type(result) == 'table' and result.shared or {}) do
        if not seen[recipe.id] then
            options[#options + 1] = { value = recipe.id, label = ('%s (shared)'):format(recipe.label) }
        end
    end
    return options
end

local fieldsFor = {}

fieldsFor.Zone = function()
    local values = form({
        { id = 'controlDuty', label = 'Clock staff on and off automatically', type = 'checkbox', default = true },
    }, 'Business perimeter')
    if not values then return nil end
    return { controlDuty = values.controlDuty }
end

fieldsFor.Blip = function()
    local values = form({
        { id = 'category', label = 'Map category', type = 'select', required = true,
          default = 'Business', options = blipCategoryOptions() },
        { id = 'name', label = 'Location or storefront name', type = 'text' },
        { id = 'sprite', label = 'Sprite', type = 'number', default = 1, min = 0, max = 900 },
        { id = 'color', label = 'Colour', type = 'number', default = 1, min = 0, max = 90 },
        { id = 'scale', label = 'Scale', type = 'number', default = 0.7, min = 0.1, max = 3.0 },
    }, 'Map blip')
    if not values then return nil end
    local coords = GetEntityCoords(PlayerPedId())
    return {
        category = values.category, name = values.name,
        sprite = values.sprite, color = values.color, scale = values.scale,
        coords = { x = coords.x, y = coords.y, z = coords.z },
    }
end

fieldsFor.StaticEntity = function() return {} end
fieldsFor.BossMenu = function() return {} end

fieldsFor.Stash = function(business)
    return form({
        { id = 'label', label = 'Label', type = 'text', required = true, default = 'Stash' },
        { id = 'id', label = 'Stash id', type = 'text', required = true, default = business.id .. '_stash' },
        { id = 'slots', label = 'Slots', type = 'number', default = Config.stash.slots, min = 1, max = 500 },
        { id = 'weight', label = 'Max weight (grams)', type = 'number', default = Config.stash.weight, min = 1000 },
        { id = 'public', label = 'Anyone may open it', type = 'checkbox' },
    }, 'Stash')
end

fieldsFor.POS = function(business)
    local lists = {}
    for name in pairs(Config.shopItems) do lists[#lists + 1] = { value = name, label = name } end
    table.sort(lists, function(a, b) return a.label < b.label end)

    local values = form({
        { id = 'label', label = 'Label', type = 'text', required = true, default = 'Till' },
        { id = 'id', label = 'Till id', type = 'text', required = true, default = business.id .. '_till' },
        { id = 'panicButton', label = 'Panic button', type = 'checkbox' },
        { id = 'closedShop', label = 'Closed shop (customers self-serve while no staff are in)', type = 'checkbox',
          description = 'Needs a business Zone. Normal tills are staffed and take itemized payments.' },
        { id = 'items', label = 'Fixed price list (closed shop)', type = 'select', options = lists,
          placeholder = 'None: Sales Items decide, staff set prices',
          visibleWhen = { fieldId = 'closedShop', equals = true } },
        { id = 'webhook', label = 'Discord webhook (optional)', type = 'text' },
    }, 'Point of sale')
    if not values then return nil end

    return {
        label = values.label, id = values.id,
        items = values.closedShop and values.items ~= nil and values.items ~= '' and { values.items } or {},
        panicButton = values.panicButton,
        closedShop = values.closedShop,
        webhook = values.webhook ~= '' and values.webhook or nil,
    }
end

fieldsFor.Crafting = function(business)
    local recipes = recipeOptions(business)
    if #recipes == 0 then
        Client.notify('No recipes exist yet. Create one on the Recipes page first.', 'error')
        return nil
    end

    local values = form({
        { id = 'label', label = 'Label', type = 'text', required = true, default = 'Crafting' },
        {
            id = 'recipes', label = 'Recipes', type = 'multiselect', required = true, searchable = true,
            description = 'Select every recipe this bench should offer. For several stations with their own recipe lists, use the Crafters page instead.',
            options = recipes,
        },
    }, 'Crafting bench')
    if not values then return nil end
    return { label = values.label, recipes = values.recipes }
end

fieldsFor.SalesItems = function()
    Client.notify('Sales items and stores are managed from their own pages.', 'error')
    return nil
end

fieldsFor.UseableItem = function(business)
    local values = form({
        { id = 'item', label = 'Item name', type = 'text', required = true },
        { id = 'useType', label = 'What happens', type = 'select', required = true, options = {
            { value = 'reward', label = 'Give a random reward' },
            { value = 'recipe', label = 'Run a recipe' },
        } },
        { id = 'consume', label = 'Items consumed per use', type = 'number', default = 1, min = 0, max = 100 },
    }, 'Useable item')
    if not values then return nil end

    if values.useType == 'recipe' then
        local recipes = {}
        for _, option in ipairs(recipeOptions(business)) do recipes[#recipes + 1] = { id = option.value, label = option.label } end
        if #recipes == 0 then
            Client.notify('No recipes exist yet. Create one on the Recipes page first.', 'error')
            return nil
        end
        local recipe = pick(recipes, 'Which recipe?')
        if not recipe then return nil end
        return { item = values.item, useType = 'recipe', consume = values.consume, recipe = recipe }
    end

    local rewards = {}
    while true do
        local reward = form({
            { id = 'item', label = ('Reward item #%d'):format(#rewards + 1), type = 'text', required = #rewards == 0 },
            { id = 'amount', label = 'Amount', type = 'number', default = 1, min = 1, max = 1000 },
            { id = 'chance', label = 'Relative weight', type = 'number', default = 1, min = 0.01 },
        }, 'Rewards', 'Leave the item blank to finish.')
        if not reward or not reward.item or reward.item == '' then break end
        rewards[#rewards + 1] = { item = reward.item, amount = reward.amount, chance = reward.chance }
    end

    if #rewards == 0 then
        Client.notify('A reward item needs at least one reward.', 'error')
        return nil
    end
    return { item = values.item, useType = 'reward', consume = values.consume, rewards = rewards }
end

---@param business table
---@param index? integer nil to append a new module
---@param moduleType? string
---@return boolean? saved
---@return integer? position
local function editModule(business, index, moduleType)
    if not moduleType then
        local options = {}
        for _, descriptor in ipairs(S.moduleTypes) do
            if not descriptor.managed then
                options[#options + 1] = { id = descriptor.type, label = descriptor.label }
            end
        end
        moduleType = pick(options, 'Add a module')
        if not moduleType then return end
    end

    local descriptor = S.moduleType[moduleType]
    local payload = fieldsFor[moduleType](business)
    if not payload then return end
    payload.moduleType = moduleType

    if descriptor.interaction ~= 'none' then
        local anchor = pickAnchor(descriptor.interaction)
        if not anchor then return end
        for key, value in pairs(anchor) do payload[key] = value end

        if moduleType ~= 'Zone' then
            local blip = pickBlip()
            if blip then payload.blip = blip end
        end
    end

    local ok, result = Kora.callback.trigger('kora_jobcreator:server:saveModule', business.id, index, payload)
    Client.notify(ok and 'Module saved. It is live now.' or (result or 'That module was rejected.'), ok and 'success' or 'error')
    return ok == true, ok and tonumber(result) or nil
end

---Edits a saved module directly, retaining its anchor and every field the
---admin does not touch. This complements Rebuild, which deliberately starts a
---new placement flow for changing a module's location.
---@param business table
---@param index integer
---@return boolean? saved
local function editModuleData(business, index)
    -- Public definitions omit webhooks; editing needs the authorized full copy.
    local module, err = Kora.callback.trigger('kora_jobcreator:server:module', business.id, index)
    if not module then
        Client.notify(err or 'That module no longer exists.', 'error')
        return false
    end

    local encoded = json.encode(module)
    local values = form({
        {
            id = 'data', label = 'Module data (JSON)', type = 'textarea', required = true,
            default = encoded, rows = 16, maxLength = 16000,
            description = 'Edit values such as labels, access, prices, recipes, or anchors. Save keeps only valid module data.',
        },
    }, ('Edit data · %s'):format(module.label), 'Placement stays as-is unless you edit its anchor fields.')
    if not values then return end

    local ok, payload = pcall(json.decode, tostring(values.data or ''))
    if not ok or type(payload) ~= 'table' then
        Client.notify('Enter a valid JSON object before saving.', 'error')
        return false
    end

    -- The module type is part of the selected module's identity here. Rebuild
    -- is the intentional path for switching types, because each type has a
    -- different field set and placement rule.
    payload.moduleType = module.moduleType
    local saved, err = Kora.callback.trigger('kora_jobcreator:server:saveModule', business.id, index, payload)
    Client.notify(saved and 'Module data saved. It is live now.' or (err or 'That data was rejected.'), saved and 'success' or 'error')
    return saved == true
end

local APP_ID = 'kora_jobcreator:management'
local openManagement
local currentState

local logTones = {
    admin = 'primary', sale = 'success', stock = 'success', payment = 'warning',
    craft = 'primary', panic = 'destructive',
}

---@param amount any
---@return string
local function money(amount)
    return ('$%d'):format(math.floor(tonumber(amount) or 0))
end

---@param businessId string
---@param previousRev? string
---@return table|nil business
local function awaitBusiness(businessId, previousRev)
    for _ = 1, 40 do
        local business = Client.definitions[businessId]
        if business and (not previousRev or business.rev ~= previousRev) then return business end
        Wait(50)
    end
    return Client.definitions[businessId]
end

---@param state table
local function loadBusinessSummary(state)
    state.balance, state.balanceError, state.logs, state.logsError = nil, nil, {}, nil
    if not state.businessId or not Client.definitions[state.businessId] then return end

    local balance, balanceError = Kora.callback.trigger('kora_jobcreator:server:balance', state.businessId)
    if balance ~= nil then state.balance = balance else state.balanceError = balanceError end

    local logs, logsError = Kora.callback.trigger('kora_jobcreator:server:logs', state.businessId, 50)
    if type(logs) == 'table' then state.logs = logs else state.logsError = logsError end

    state.recipes, state.recipesError = { business = {}, shared = {} }, nil
    if isAdmin then
        local recipes, recipesError = Kora.callback.trigger('kora_jobcreator:server:recipes', state.businessId)
        if type(recipes) == 'table' then state.recipes = recipes else state.recipesError = recipesError end
    end
end

---@return table[] businesses
local function manageableBusinesses()
    local businesses = {}
    for _, business in pairs(Client.definitions) do
        if isAdmin or Client.isBoss(business) then businesses[#businesses + 1] = business end
    end
    table.sort(businesses, function(a, b) return a.label < b.label end)
    return businesses
end

---@param module table
---@return string
local function anchorLabel(module)
    local coords = module.zoneType and module.coords or (module.coords and module.coords[1])
    if not coords then return 'No world anchor' end
    return ('%.1f, %.1f, %.1f'):format(coords.x or 0.0, coords.y or 0.0, coords.z or 0.0)
end

local appUpdate

-- ---------------------------------------------------------------------------
-- Business workspace pages: Sales Items, Stores, Recipes, Crafters.
--
-- Every edit here is the same round trip the Modules page uses: fetch the
-- authorised private copy of the module, change it, and hand the whole module
-- back to `saveModule`, which validates it with the one schema before anything
-- is written. There is no second write path for these pages.
-- ---------------------------------------------------------------------------

---@param name string
---@return string label
local function itemLabel(name)
    local definition = Kora.shared.get('items', name)
    return definition and definition.label or name
end

---@param name string
---@return string|nil
local function itemImage(name)
    local definition = Kora.shared.get('items', name)
    local image = definition and definition.image
    if type(image) ~= 'string' or image == '' then return nil end
    if image:match('^https?://') or image:match('^nui://') then return image end
    return ('nui://kora_inventory/images/%s'):format(image)
end

---@param exclude? table<string, true>
---@return table[] options
local function itemOptions(exclude)
    local options = {}
    for _, item in ipairs(Kora.shared.all('items')) do
        local name = item.name
        if type(name) == 'string' and not (exclude and exclude[name]) then
            options[#options + 1] = { value = name, label = ('%s (%s)'):format(item.label or name, name) }
        end
    end
    table.sort(options, function(a, b) return a.label:lower() < b.label:lower() end)
    return options
end

---@param business table
---@return integer|nil index, table|nil module
local function salesModule(business)
    for index, module in ipairs(business.modules) do
        if module.moduleType == 'SalesItems' then return index, module end
    end
end

---@param point table
---@return string
local function pointLabel(point)
    local text = ('%.1f, %.1f, %.1f'):format(point.x or 0.0, point.y or 0.0, point.z or 0.0)
    return point.model and ('%s · %s'):format(text, point.model) or text
end

---@param points table[]
---@return table[] options
local function locationOptions(points)
    local options = {}
    for index, point in ipairs(points or {}) do
        options[#options + 1] = { value = tostring(index), label = ('#%d · %s'):format(index, pointLabel(point)) }
    end
    return options
end

---Fetches the authorised copy of a module (or starts a new one), applies
---`mutate`, and saves the result through the normal module write path.
---@param business table
---@param index? integer nil to create
---@param mutate fun(module: table|nil): table|nil, string|nil
---@return boolean ok, string|nil err
local function changeModule(business, index, mutate)
    local module
    if index then
        local fetched, err = Kora.callback.trigger('kora_jobcreator:server:module', business.id, index)
        if not fetched then return false, err or 'That module no longer exists.' end
        module = fetched
    end
    local payload, mutateErr = mutate(module)
    if not payload then return false, mutateErr end
    local previousRev = business.rev
    local ok, err = Kora.callback.trigger('kora_jobcreator:server:saveModule', business.id, index, payload)
    if not ok then return false, err or 'That change was rejected.' end
    awaitBusiness(business.id, previousRev)
    return true
end

---@param business table
---@param mutate fun(module: table): table|nil, string|nil
---@return boolean ok, string|nil err
local function changeSales(business, mutate)
    local index = salesModule(business)
    return changeModule(business, index, function(module)
        module = module or { moduleType = 'SalesItems', label = 'Sales items', items = {}, stores = {} }
        module.items, module.stores = module.items or {}, module.stores or {}
        return mutate(module)
    end)
end

---@param list table[]
---@param id string
---@return table|nil entry, integer|nil position
local function findById(list, id)
    for position, entry in ipairs(list or {}) do
        if entry.id == id then return entry, position end
    end
end

---Aim at a spot (or at a specific prop) and press E. Returns the hit point,
---faced the way the player is facing, and the prop model if one was required.
---@param model? string
---@return table|nil point
local function pickPoint(model)
    local hash = model and joaat(model)
    if model and not IsModelValid(hash) then
        Client.notify(('"%s" is not a valid model.'):format(model), 'error')
        return nil
    end
    local prompt = Kora.textui.show(model
        and ('Aim at a %s and press ~b~E~s~ -- ~r~Backspace~s~ to cancel'):format(model)
        or 'Aim at the spot and press ~b~E~s~ -- ~r~Backspace~s~ to cancel')
    local point

    while true do
        Wait(0)
        local hit, coords, entity = Kora.raycast.fromCamera(25.0)
        local valid = hit and coords ~= nil
            and (not hash or (entity and entity ~= 0 and GetEntityModel(entity) == hash))
        if hit and coords then
            DrawMarker(28, coords.x, coords.y, coords.z, 0, 0, 0, 0, 0, 0, 0.2, 0.2, 0.2,
                valid and 0 or 220, valid and 200 or 40, 120, 140, false, false, 2, nil, nil, false)
        end
        if IsControlJustReleased(0, 202) then break end
        if IsControlJustReleased(0, 38) and valid then
            point = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(PlayerPedId()), model = model }
            break
        end
    end

    Kora.textui.hide(prompt)
    return point
end

---@param recipe? table
---@return table[] fields
local function recipeFields(recipe)
    recipe = recipe or {}
    local function rows(entries)
        local out = {}
        for _, entry in ipairs(entries or {}) do
            out[#out + 1] = { key = entry.item, value = json.encode(entry.amount or 1) }
        end
        return out
    end
    local function entryField(id, label, entries, required)
        return {
            id = id, label = label, type = 'key-value', keyMode = 'string', required = required,
            keyLabel = 'Item name', valueLabel = 'Amount', addRowLabel = 'Add item', removeRowLabel = 'Remove',
            valueField = { id = 'amount', label = 'Amount', type = 'number', min = 1, max = 1000, wholeNumber = true },
            default = rows(entries),
        }
    end
    return {
        { id = 'label', label = 'Recipe name', type = 'text', required = true, maxLength = 64, default = recipe.label },
        entryField('ingredients', 'Ingredients', recipe.ingredients, false),
        entryField('give', 'Produces', recipe.give, true),
        { id = 'seconds', label = 'Craft time (seconds)', type = 'number', min = 0, max = 600, step = 0.5,
            default = recipe.time and recipe.time / 1000 or 5 },
        { id = 'progressLabel', label = 'Progress text', type = 'text', maxLength = 64, default = recipe.progressLabel },
        { id = 'completeLabel', label = 'Completion message', type = 'text', maxLength = 128, default = recipe.completeLabel },
    }
end

---@param values table
---@param previous? table keeps fields the form does not edit (skills, animation)
---@return table recipe payload
local function recipePayload(values, previous)
    local function entries(rows)
        local out = {}
        for _, row in ipairs(type(rows) == 'table' and rows or {}) do
            local name = type(row.key) == 'string' and row.key:lower():gsub('^%s+', ''):gsub('%s+$', '') or ''
            -- Rows carry their value as JSON text; accept a bare number too.
            local ok, decoded = pcall(json.decode, tostring(row.value))
            local amount = (ok and tonumber(decoded)) or tonumber(row.value)
            if name ~= '' then out[#out + 1] = { item = name, amount = amount and math.floor(amount) or 1 } end
        end
        return out
    end
    local recipe = previous and json.decode(json.encode(previous)) or {}
    recipe.id, recipe.usages, recipe.output = nil, nil, nil
    recipe.label = values.label
    recipe.ingredients = entries(values.ingredients)
    recipe.give = entries(values.give)
    recipe.time = math.floor((tonumber(values.seconds) or 0) * 1000)
    recipe.progressLabel = values.progressLabel ~= '' and values.progressLabel or nil
    recipe.completeLabel = values.completeLabel ~= '' and values.completeLabel or nil
    return recipe
end

---@param entries table[]|nil
---@return string
local function entrySummary(entries)
    local parts = {}
    for _, entry in ipairs(entries or {}) do parts[#parts + 1] = ('%dx %s'):format(entry.amount or 1, itemLabel(entry.item)) end
    return #parts > 0 and table.concat(parts, ', ') or 'Nothing'
end

---@param state table
---@return table[] options every recipe a category may reference
local function categoryRecipeOptions(state)
    local options, seen = {}, {}
    for _, recipe in ipairs(state.recipes and state.recipes.business or {}) do
        seen[recipe.id] = true
        options[#options + 1] = { value = recipe.id, label = ('%s (business)'):format(recipe.label) }
    end
    for _, recipe in ipairs(state.recipes and state.recipes.shared or {}) do
        if not seen[recipe.id] then options[#options + 1] = { value = recipe.id, label = ('%s (shared)'):format(recipe.label) } end
    end
    return options
end

---@param state table
---@param id string
---@return string
local function recipeName(state, id)
    for _, recipe in ipairs(state.recipes and state.recipes.business or {}) do
        if recipe.id == id then return recipe.label end
    end
    local shared = Config.recipes[id]
    return shared and shared.label or id
end

---@param state table
---@param business table
---@return table[] tabs
local function workspaceTabs(state, business)
    local _, sales = salesModule(business)
    local salesItems = sales and sales.items or {}
    local selling = {}
    for _, name in ipairs(salesItems) do selling[name] = true end

    -- Sales Items ---------------------------------------------------------
    local salesCards = {}
    for _, name in ipairs(salesItems) do
        salesCards[#salesCards + 1] = {
            id = name, label = itemLabel(name), description = name, image = itemImage(name), icon = 'package',
            actions = { { id = 'sales:remove', label = 'Remove', icon = 'trash-2', variant = 'outline' } },
        }
    end

    -- Stores ----------------------------------------------------------------
    local allItems = itemOptions()
    local storeCards = {}
    for _, store in ipairs(sales and sales.stores or {}) do
        local children = {}
        for _, entry in ipairs(store.items) do
            children[#children + 1] = {
                id = ('%s|%s'):format(store.id, entry.item), label = itemLabel(entry.item),
                description = ('$%d each'):format(entry.price), image = itemImage(entry.item), icon = 'package',
                actions = {
                    { id = 'stores:price-item', label = 'Price', icon = 'dollar-sign', variant = 'outline', fields = {
                        { id = 'price', label = 'Price per item', type = 'number', required = true, min = 0,
                            max = Config.pos.maxPrice, wholeNumber = true, default = entry.price },
                    } },
                    { id = 'stores:remove-item', label = 'Remove', icon = 'trash-2', variant = 'outline' },
                },
            }
        end
        local locationsAvailable = #store.locations > 0
        storeCards[#storeCards + 1] = {
            id = store.id, label = store.label, icon = 'store', badge = #store.items,
            description = ('%d item(s) · %d location(s) · paid by %s'):format(#store.items, #store.locations,
                store.payFrom == 'business' and 'the business' or 'the employee'),
            tone = locationsAvailable and 'neutral' or 'warning',
            metadata = {
                { label = 'Locations', value = locationsAvailable and #store.locations or 'None placed yet',
                    tone = locationsAvailable and 'success' or 'warning' },
            },
            children = children,
            actions = {
                { id = 'stores:add-item', label = 'Add item', icon = 'plus', variant = 'primary', fields = {
                    { id = 'item', label = 'Item', type = 'select', required = true, searchable = true, options = allItems },
                    { id = 'price', label = 'Price per item', type = 'number', required = true, min = 0,
                        max = Config.pos.maxPrice, wholeNumber = true, default = 0 },
                } },
                { id = 'stores:place', label = 'Place store', icon = 'map-pin', closeBeforeAction = true, fields = {
                    { id = 'model', label = 'Prop model (optional)', type = 'text', maxLength = 64,
                        description = 'Leave blank to aim at any surface, or enter a model to require aiming at that prop.' },
                } },
                { id = 'stores:remove-location', label = 'Remove location', icon = 'map-pin-off', variant = 'outline',
                    disabled = not locationsAvailable, fields = locationsAvailable and {
                        { id = 'location', label = 'Location', type = 'select', required = true, options = locationOptions(store.locations) },
                    } or nil },
                { id = 'stores:edit', label = 'Settings', icon = 'pencil', variant = 'outline', fields = {
                    { id = 'label', label = 'Name', type = 'text', required = true, maxLength = 64, default = store.label },
                    { id = 'payFrom', label = 'Who pays', type = 'select', required = true, default = store.payFrom, options = {
                        { value = 'player', label = ('The employee (%s)'):format(Config.stores.account) },
                        { value = 'business', label = 'The business account' },
                    } },
                } },
                { id = 'stores:delete', label = 'Delete', icon = 'trash-2', variant = 'destructive',
                    confirm = ('Delete the %s store and all of its locations?'):format(store.label) },
            },
        }
    end

    -- Recipes -----------------------------------------------------------------
    local recipeCards = {}
    for _, recipe in ipairs(state.recipes and state.recipes.business or {}) do
        local output = recipe.give and recipe.give[1]
        local usages = recipe.usages or {}
        recipeCards[#recipeCards + 1] = {
            id = recipe.id, label = recipe.label, icon = 'chef-hat',
            image = output and itemImage(output.item),
            description = ('Makes %s'):format(entrySummary(recipe.give)),
            metadata = {
                { label = 'Ingredients', value = entrySummary(recipe.ingredients) },
                { label = 'Time', value = ('%.1fs'):format((recipe.time or 0) / 1000) },
                { label = 'Used by', value = #usages > 0 and table.concat(usages, ', ') or 'Nothing yet',
                    tone = #usages > 0 and 'success' or 'neutral' },
            },
            actions = {
                { id = 'recipes:edit', label = 'Edit', icon = 'pencil', variant = 'outline', fields = recipeFields(recipe) },
                { id = 'recipes:delete', label = 'Delete', icon = 'trash-2', variant = 'destructive',
                    disabled = #usages > 0, confirm = ('Delete the %s recipe?'):format(recipe.label) },
            },
        }
    end
    local sharedCards = {}
    for _, recipe in ipairs(state.recipes and state.recipes.shared or {}) do
        sharedCards[#sharedCards + 1] = { id = 'shared:' .. recipe.id, label = recipe.label, description = recipe.id, icon = 'book-open' }
    end

    -- Crafters ----------------------------------------------------------------
    local recipeChoices = categoryRecipeOptions(state)
    local crafterCards = {}
    for index, module in ipairs(business.modules) do
        if module.moduleType == 'Crafting' then
            local categories = module.crafters or {
                { id = 'default', label = 'Bench recipes', recipes = module.recipes, locations = nil },
            }
            local children = {}
            for _, category in ipairs(categories) do
                local names = {}
                for _, id in ipairs(category.recipes or {}) do names[#names + 1] = recipeName(state, id) end
                local key = ('%d|%s'):format(index, category.id)
                local actions = {
                    { id = 'crafters:recipes', label = 'Recipes', icon = 'list-checks', variant = 'primary', fields = {
                        { id = 'recipes', label = 'Recipes', type = 'multiselect', searchable = true,
                            options = recipeChoices, default = category.recipes or {},
                            required = not module.crafters },
                    } },
                }
                if module.crafters then
                    local placed = #category.locations > 0
                    actions[#actions + 1] = { id = 'crafters:place', label = 'Place location', icon = 'map-pin', closeBeforeAction = true, fields = {
                        { id = 'model', label = 'Prop model (optional)', type = 'text', maxLength = 64,
                            description = 'Leave blank to aim at any surface, or enter a model to require aiming at that prop.' },
                    } }
                    actions[#actions + 1] = { id = 'crafters:remove-location', label = 'Remove location', icon = 'map-pin-off',
                        variant = 'outline', disabled = not placed, fields = placed and {
                            { id = 'location', label = 'Location', type = 'select', required = true, options = locationOptions(category.locations) },
                        } or nil }
                    actions[#actions + 1] = { id = 'crafters:rename-category', label = 'Rename', icon = 'pencil', variant = 'outline', fields = {
                        { id = 'label', label = 'Name', type = 'text', required = true, maxLength = 64, default = category.label },
                    } }
                    actions[#actions + 1] = { id = 'crafters:delete-category', label = 'Delete', icon = 'trash-2',
                        variant = 'destructive', confirm = ('Delete the %s category?'):format(category.label) }
                end
                children[#children + 1] = {
                    id = key, label = category.label, icon = 'layers', badge = #(category.recipes or {}),
                    description = #names > 0 and table.concat(names, ', ') or 'No recipes assigned yet',
                    metadata = module.crafters and {
                        { label = 'Locations', value = #category.locations > 0 and #category.locations or 'None placed yet',
                            tone = #category.locations > 0 and 'success' or 'warning' },
                    } or nil,
                    actions = actions,
                }
            end

            local actions = {}
            if module.crafters then
                actions[#actions + 1] = { id = 'crafters:add-category', label = 'Add category', icon = 'plus', variant = 'primary', fields = {
                    { id = 'label', label = 'Category name', type = 'text', required = true, maxLength = 64,
                        placeholder = 'Drinks, Prep, Grill…' },
                } }
            end
            actions[#actions + 1] = { id = 'crafters:rename', label = 'Rename', icon = 'pencil', variant = 'outline', fields = {
                { id = 'label', label = 'Name', type = 'text', required = true, maxLength = 64, default = module.label },
            } }
            actions[#actions + 1] = { id = 'crafters:delete', label = 'Delete', icon = 'trash-2', variant = 'destructive',
                confirm = ('Delete the %s crafter?'):format(module.label) }

            crafterCards[#crafterCards + 1] = {
                id = tostring(index), label = module.label, icon = 'hammer',
                description = module.crafters and ('%d categor%s'):format(#module.crafters, #module.crafters == 1 and 'y' or 'ies')
                    or ('Single bench at %s'):format(anchorLabel(module)),
                children = children, actions = actions,
            }
        end
    end

    -- Tills and stashes -------------------------------------------------------
    local tillCards, stashCards = {}, {}
    for index, module in ipairs(business.modules) do
        if module.moduleType == 'POS' then
            tillCards[#tillCards + 1] = {
                id = tostring(index), label = module.label, icon = module.closedShop and 'store' or 'credit-card',
                description = module.closedShop and ('Closed shop · %s'):format(module.id) or ('Staffed till · %s'):format(module.id),
                metadata = {
                    { label = 'Location', value = anchorLabel(module) },
                    { label = 'Customers pay with', value = module.currency == 'bank' and 'Bank' or 'Cash' },
                    { label = 'Panic button', value = module.panicButton and 'Yes' or 'No' },
                },
                actions = {
                    { id = 'tills:settings', label = 'Settings', icon = 'pencil', variant = 'outline', fields = {
                        { id = 'label', label = 'Label', type = 'text', required = true, maxLength = 64, default = module.label },
                        { id = 'closedShop', label = 'Closed shop (customers self-serve while no staff are in)', type = 'checkbox',
                            default = module.closedShop == true },
                        { id = 'currency', label = 'Closed-shop customers pay with', type = 'select', default = module.currency, options = {
                            { value = 'cash', label = 'Cash' }, { value = 'bank', label = 'Bank' },
                        } },
                        { id = 'panicButton', label = 'Panic button', type = 'checkbox', default = module.panicButton == true },
                    } },
                },
            }
        elseif module.moduleType == 'Stash' then
            stashCards[#stashCards + 1] = {
                id = tostring(index), label = module.label, icon = 'archive', description = module.id,
                metadata = {
                    { label = 'Location', value = anchorLabel(module) },
                    { label = 'Slots', value = module.slots },
                    { label = 'Max weight', value = ('%d g'):format(module.weight or 0) },
                    { label = 'Access', value = module.public and 'Anyone' or business.job },
                },
                actions = {
                    { id = 'stashes:settings', label = 'Settings', icon = 'pencil', variant = 'outline', fields = {
                        { id = 'label', label = 'Label', type = 'text', required = true, maxLength = 64, default = module.label },
                        { id = 'slots', label = 'Slots', type = 'number', required = true, min = 1, max = 500, wholeNumber = true,
                            default = module.slots },
                        { id = 'weight', label = 'Max weight (grams)', type = 'number', required = true, min = 1000,
                            max = 100000000, wholeNumber = true, default = module.weight },
                        { id = 'public', label = 'Anyone may open it', type = 'checkbox', default = module.public == true },
                    } },
                },
            }
        end
    end

    return {
        {
            id = 'tills', label = 'Tills', badge = #tillCards, content = {
                title = 'Tills and closed shops',
                description = 'Staffed tills take itemized payments from the Sales Items list. A closed shop is a customer shelf staff restock, usable while nobody is working.',
                actions = {
                    { id = 'tills:create', label = 'Place a till', icon = 'plus', variant = 'primary', closeBeforeAction = true },
                },
                blocks = { {
                    type = 'list', id = 'business-tills', layout = 'cards', searchable = true, pageSize = 12,
                    searchPlaceholder = 'Search tills…', items = tillCards, empty = 'No tills yet.',
                } },
            },
        },
        {
            id = 'stashes', label = 'Stashes', badge = #stashCards, content = {
                title = 'Stashes',
                description = 'Changing a stash\'s label, slots or weight keeps its contents. Use Modules → Rebuild to move one.',
                actions = {
                    { id = 'stashes:create', label = 'Place a stash', icon = 'plus', variant = 'primary', closeBeforeAction = true },
                },
                blocks = { {
                    type = 'list', id = 'business-stashes', layout = 'cards', searchable = true, pageSize = 12,
                    searchPlaceholder = 'Search stashes…', items = stashCards, empty = 'No stashes yet.',
                } },
            },
        },
        {
            id = 'sales', label = 'Sales Items', badge = #salesItems, content = {
                title = 'Sales items',
                description = 'Items staff may sell through itemized payments, and what a closed shop accepts when restocked. Applies to every till.',
                actions = {
                    { id = 'sales:add', label = 'Add items', icon = 'plus', variant = 'primary', fields = {
                        { id = 'items', label = 'Items', type = 'multiselect', required = true, searchable = true,
                            options = itemOptions(selling) },
                    } },
                },
                blocks = { {
                    type = 'list', id = 'sales-items', layout = 'cards', cardStyle = 'compact', searchable = true,
                    pageSize = 24, searchPlaceholder = 'Search sales items…', items = salesCards,
                    empty = 'No sales items yet. Itemized payments need at least one.',
                } },
            },
        },
        {
            id = 'stores', label = 'Stores', badge = #storeCards, content = {
                title = 'Employee stores',
                description = 'Priced ingredient pickups with unlimited supply. Create a store, add items, then place one or more pickup locations.',
                actions = {
                    { id = 'stores:create', label = 'Create store', icon = 'plus', variant = 'primary', fields = {
                        { id = 'label', label = 'Store name', type = 'text', required = true, maxLength = 64, placeholder = 'Produce, Meat, Bar supplies…' },
                        { id = 'payFrom', label = 'Who pays', type = 'select', required = true, default = 'player', options = {
                            { value = 'player', label = ('The employee (%s)'):format(Config.stores.account) },
                            { value = 'business', label = 'The business account' },
                        } },
                    } },
                },
                blocks = { {
                    type = 'list', id = 'business-stores', layout = 'list', searchable = true, pageSize = 10,
                    searchPlaceholder = 'Search stores…', items = storeCards, empty = 'No stores yet.',
                } },
            },
        },
        {
            id = 'recipes', label = 'Recipes', badge = #recipeCards, content = {
                title = 'Business recipes',
                description = state.recipesError or 'Recipes saved for this business only. Assign them to crafter categories or useable items.',
                actions = {
                    { id = 'recipes:create', label = 'Create recipe', icon = 'plus', variant = 'primary', fields = recipeFields() },
                },
                blocks = {
                    {
                        type = 'list', id = 'business-recipes', layout = 'cards', cardStyle = 'compact', searchable = true,
                        pageSize = 12, searchPlaceholder = 'Search recipes…', items = recipeCards,
                        empty = 'No business recipes yet.',
                    },
                    {
                        type = 'list', id = 'shared-recipes', title = 'Shared library (shared/recipes, read-only)',
                        layout = 'list', searchable = true, pageSize = 8, items = sharedCards,
                        empty = 'No shared recipes are configured.',
                    },
                },
            },
        },
        {
            id = 'crafters', label = 'Crafters', badge = #crafterCards, content = {
                title = 'Crafters',
                description = 'A crafter groups categories such as Drinks, Prep or Grill. Each category has its own recipes and one or more placed locations.',
                actions = {
                    { id = 'crafters:create', label = 'Create crafter', icon = 'plus', variant = 'primary', fields = {
                        { id = 'label', label = 'Crafter name', type = 'text', required = true, maxLength = 64, placeholder = 'Kitchen' },
                    } },
                },
                blocks = { {
                    type = 'list', id = 'business-crafters', layout = 'list', searchable = true, pageSize = 10,
                    searchPlaceholder = 'Search crafters…', items = crafterCards, empty = 'No crafters yet.',
                } },
            },
        },
    }
end

---@param state table
---@param ok boolean
---@param err? string
---@param message string
---@return table result
local function workspaceResult(state, ok, err, message)
    if not ok then return { notice = { tone = 'destructive', message = err or 'That change was rejected.' } } end
    loadBusinessSummary(state)
    return { update = appUpdate(state), notice = { tone = 'success', message = message } }
end

---Places a world point after the console has closed, saves it, then reopens
---the console on the page the admin came from.
---@param state table
---@param business table
---@param tabId string
---@param model? string
---@param apply fun(point: table): boolean, string|nil
local function placeAndResume(state, business, tabId, model, apply)
    CreateThread(function()
        local point = pickPoint(model)
        if point then
            local ok, err = apply(point)
            Client.notify(ok and 'Location saved. It is live now.' or (err or 'That location was rejected.'), ok and 'success' or 'error')
        end
        state.businessId = business.id
        loadBusinessSummary(state)
        openManagement(state, 'management', tabId)
    end)
end

---@param state table
---@param business table
---@param actionId string
---@param itemId? string
---@param values table
---@return table|nil result, boolean handled
local function workspaceAction(state, business, actionId, itemId, values)
    -- World placement closes the console first, so by the time a location is
    -- saved the replicated definition may have moved on. Always edit the
    -- latest one.
    local function current() return Client.definitions[business.id] or business end
    local function modelValue()
        local model = type(values.model) == 'string' and values.model:gsub('^%s+', ''):gsub('%s+$', '') or ''
        return model ~= '' and model or nil
    end

    -- Sales Items
    if actionId == 'sales:add' then
        local ok, err = changeSales(business, function(module)
            for _, name in ipairs(type(values.items) == 'table' and values.items or {}) do module.items[#module.items + 1] = name end
            return module
        end)
        return workspaceResult(state, ok, err, 'Sales items updated.'), true
    elseif actionId == 'sales:remove' then
        local ok, err = changeSales(business, function(module)
            for position, name in ipairs(module.items) do
                if name == itemId then table.remove(module.items, position); break end
            end
            return module
        end)
        return workspaceResult(state, ok, err, 'Removed from sales items.'), true
    end

    -- Stores
    if actionId:sub(1, 7) == 'stores:' then
        local storeId, itemName = tostring(itemId or ''):match('^([^|]+)|?(.*)$')
        local function withStore(mutate)
            return changeSales(current(), function(module)
                local store, position = findById(module.stores, storeId)
                if not store then return nil, 'That store no longer exists.' end
                return mutate(module, store, position)
            end)
        end

        if actionId == 'stores:create' then
            local ok, err = changeSales(business, function(module)
                module.stores[#module.stores + 1] = { label = values.label, payFrom = values.payFrom, items = {}, locations = {} }
                return module
            end)
            return workspaceResult(state, ok, err, 'Store created. Add items, then place it.'), true
        elseif actionId == 'stores:add-item' then
            local ok, err = withStore(function(module, store)
                for _, entry in ipairs(store.items) do
                    if entry.item == values.item then entry.price = values.price; return module end
                end
                store.items[#store.items + 1] = { item = values.item, price = values.price }
                return module
            end)
            return workspaceResult(state, ok, err, 'Store item saved.'), true
        elseif actionId == 'stores:price-item' or actionId == 'stores:remove-item' then
            local ok, err = withStore(function(module, store)
                for position, entry in ipairs(store.items) do
                    if entry.item == itemName then
                        if actionId == 'stores:remove-item' then table.remove(store.items, position) else entry.price = values.price end
                        return module
                    end
                end
                return nil, 'That item is no longer in this store.'
            end)
            return workspaceResult(state, ok, err, actionId == 'stores:remove-item' and 'Store item removed.' or 'Price updated.'), true
        elseif actionId == 'stores:edit' then
            local ok, err = withStore(function(module, store)
                store.label, store.payFrom = values.label, values.payFrom
                return module
            end)
            return workspaceResult(state, ok, err, 'Store updated.'), true
        elseif actionId == 'stores:remove-location' then
            local ok, err = withStore(function(module, store)
                local position = math.floor(tonumber(values.location) or 0)
                if not store.locations[position] then return nil, 'That location no longer exists.' end
                table.remove(store.locations, position)
                return module
            end)
            return workspaceResult(state, ok, err, 'Location removed.'), true
        elseif actionId == 'stores:delete' then
            local ok, err = withStore(function(module, _, position)
                table.remove(module.stores, position)
                return module
            end)
            return workspaceResult(state, ok, err, 'Store deleted.'), true
        elseif actionId == 'stores:place' then
            placeAndResume(state, business, 'stores', modelValue(), function(point)
                return withStore(function(module, store)
                    store.locations[#store.locations + 1] = point
                    return module
                end)
            end)
            return nil, true
        end
    end

    -- Till and stash settings keep the anchor and every field the form does
    -- not show.
    if actionId == 'tills:settings' or actionId == 'stashes:settings' then
        local wanted = actionId == 'tills:settings' and 'POS' or 'Stash'
        local ok, err = changeModule(current(), tonumber(itemId), function(module)
            if not module or module.moduleType ~= wanted then return nil, 'That module no longer exists.' end
            module.label = values.label
            if wanted == 'POS' then
                module.closedShop = values.closedShop == true
                module.currency = values.currency or module.currency
                module.panicButton = values.panicButton == true
            else
                module.slots, module.weight, module.public = values.slots, values.weight, values.public == true
            end
            return module
        end)
        return workspaceResult(state, ok, err, 'Settings saved.'), true
    end

    -- Recipes
    if actionId == 'recipes:create' or actionId == 'recipes:edit' then
        local previous
        if actionId == 'recipes:edit' then
            for _, recipe in ipairs(state.recipes and state.recipes.business or {}) do
                if recipe.id == itemId then previous = recipe end
            end
            if not previous then return { notice = { tone = 'destructive', message = 'That recipe no longer exists.' } }, true end
        end
        local saved, err = Kora.callback.trigger('kora_jobcreator:server:saveRecipe', business.id,
            previous and previous.id or nil, recipePayload(values, previous))
        return workspaceResult(state, saved ~= nil, err, previous and 'Recipe updated.' or 'Recipe created.'), true
    elseif actionId == 'recipes:delete' then
        local ok, err = Kora.callback.trigger('kora_jobcreator:server:deleteRecipe', business.id, itemId)
        return workspaceResult(state, ok == true, err, 'Recipe deleted.'), true
    end

    -- Crafters
    if actionId:sub(1, 9) == 'crafters:' then
        local index, categoryId = tostring(itemId or ''):match('^(%d+)|?(.*)$')
        index = tonumber(index)
        local function withCrafter(mutate)
            if not index then return false, 'That crafter no longer exists.' end
            return changeModule(current(), index, function(module)
                if not module or module.moduleType ~= 'Crafting' then return nil, 'That crafter no longer exists.' end
                return mutate(module)
            end)
        end
        local function withCategory(mutate)
            return withCrafter(function(module)
                if categoryId == 'default' and not module.crafters then return mutate(module, nil) end
                local category, position = findById(module.crafters, categoryId)
                if not category then return nil, 'That category no longer exists.' end
                return mutate(module, category, position)
            end)
        end

        if actionId == 'crafters:create' then
            local ok, err = changeModule(business, nil, function()
                return { moduleType = 'Crafting', label = values.label, crafters = {} }
            end)
            return workspaceResult(state, ok, err, 'Crafter created. Add a category next.'), true
        elseif actionId == 'crafters:rename' then
            local ok, err = withCrafter(function(module) module.label = values.label; return module end)
            return workspaceResult(state, ok, err, 'Crafter renamed.'), true
        elseif actionId == 'crafters:delete' then
            if not index or not business.modules[index] then
                return { notice = { tone = 'destructive', message = 'That crafter no longer exists.' } }, true
            end
            local previousRev = business.rev
            local ok, err = Kora.callback.trigger('kora_jobcreator:server:removeModule', business.id, index)
            if ok then awaitBusiness(business.id, previousRev) end
            return workspaceResult(state, ok == true, err, 'Crafter deleted.'), true
        elseif actionId == 'crafters:add-category' then
            local ok, err = withCrafter(function(module)
                if not module.crafters then return nil, 'A single bench has no categories.' end
                module.crafters[#module.crafters + 1] = { label = values.label, recipes = {}, locations = {} }
                return module
            end)
            return workspaceResult(state, ok, err, 'Category added. Assign recipes and place it.'), true
        elseif actionId == 'crafters:recipes' then
            local ok, err = withCategory(function(module, category)
                local chosen = type(values.recipes) == 'table' and values.recipes or {}
                if category then category.recipes = chosen else module.recipes = chosen end
                return module
            end)
            return workspaceResult(state, ok, err, 'Recipes updated.'), true
        elseif actionId == 'crafters:rename-category' then
            local ok, err = withCategory(function(module, category)
                if not category then return nil, 'Rename the bench instead.' end
                category.label = values.label
                return module
            end)
            return workspaceResult(state, ok, err, 'Category renamed.'), true
        elseif actionId == 'crafters:delete-category' then
            local ok, err = withCategory(function(module, category, position)
                if not category then return nil, 'Delete the bench instead.' end
                table.remove(module.crafters, position)
                return module
            end)
            return workspaceResult(state, ok, err, 'Category deleted.'), true
        elseif actionId == 'crafters:remove-location' then
            local ok, err = withCategory(function(module, category)
                local position = math.floor(tonumber(values.location) or 0)
                if not category or not category.locations[position] then return nil, 'That location no longer exists.' end
                table.remove(category.locations, position)
                return module
            end)
            return workspaceResult(state, ok, err, 'Location removed.'), true
        elseif actionId == 'crafters:place' then
            placeAndResume(state, business, 'crafters', modelValue(), function(point)
                return withCategory(function(module, category)
                    if not category then return nil, 'A single bench is moved with Rebuild.' end
                    category.locations[#category.locations + 1] = point
                    return module
                end)
            end)
            return nil, true
        end
    end

    return nil, false
end

---@param state table
---@return table definition
local function appDefinition(state)
    local businessCards = {}
    for _, business in ipairs(manageableBusinesses()) do
        businessCards[#businessCards + 1] = {
            id = business.id,
            label = business.label,
            description = business.job,
            icon = 'building-2',
            badge = #business.modules,
            tone = business.id == state.businessId and 'primary' or 'neutral',
            action = 'businesses:select',
            metadata = {
                { label = 'Job', value = business.job },
                { label = 'Modules', value = #business.modules },
                { label = 'Staff present', value = Client.staff[business.id] or 0,
                    tone = (Client.staff[business.id] or 0) > 0 and 'success' or 'neutral' },
            },
        }
    end

    local directoryActions = {}
    if isAdmin and #state.jobs > 0 then
        directoryActions[#directoryActions + 1] = {
            id = 'businesses:create', label = 'Create business', icon = 'plus',
            variant = 'primary', closeBeforeAction = true,
            fields = {
                { id = 'label', label = 'Business name', type = 'text', required = true, maxLength = 128 },
                { id = 'job', label = 'Job', type = 'select', required = true, options = state.jobs },
            },
            confirm = 'Create this business, then place its first module?',
        }
    end

    local navigation = {
        {
            id = 'businesses', label = 'Businesses', icon = 'building-2', badge = #businessCards,
            content = {
                title = 'Business directory',
                description = isAdmin and 'Open a business to manage its modules and activity.'
                    or 'Businesses where your current grade has management access.',
                actions = directoryActions,
                blocks = {
                    {
                        type = 'list', id = 'business-directory', layout = 'cards', searchable = true,
                        pageSize = 8, searchPlaceholder = 'Search businesses or jobs…', items = businessCards,
                        empty = isAdmin and 'No businesses exist yet.' or 'You do not manage any business.',
                    },
                },
            },
        },
    }

    local business = state.businessId and Client.definitions[state.businessId]
    if business and (isAdmin or Client.isBoss(business)) then
        local overviewActions = {
            { id = 'businesses:refresh', label = 'Refresh', icon = 'refresh-cw', variant = 'outline' },
        }
        if isAdmin and #state.jobs > 0 then
            overviewActions[#overviewActions + 1] = {
                id = 'businesses:edit', label = 'Rename or reassign', icon = 'pencil',
                fields = {
                    { id = 'label', label = 'Name', type = 'text', required = true,
                        default = business.label, maxLength = 128 },
                    { id = 'job', label = 'Job', type = 'select', required = true,
                        options = state.jobs, default = business.job },
                },
            }
            overviewActions[#overviewActions + 1] = {
                id = 'businesses:delete', label = 'Delete business', icon = 'trash-2',
                variant = 'destructive',
                confirm = ('Delete %s and every module it owns? Stashes and till stock are left untouched.'):format(business.label),
            }
        end

        local moduleCards = {}
        for index, module in ipairs(business.modules) do
            local moduleActions = {
                {
                    id = 'businesses:edit-module-data', label = 'Edit data', icon = 'file-pen-line',
                    variant = 'outline', closeBeforeAction = true,
                },
            }
            -- Sales items and category crafters have no anchor of their own;
            -- their pages place their locations instead.
            if not (S.moduleType[module.moduleType].managed or module.crafters) then
                moduleActions[#moduleActions + 1] = {
                    id = 'businesses:edit-module', label = 'Rebuild', icon = 'pencil-ruler',
                    closeBeforeAction = true,
                }
            end
            moduleActions[#moduleActions + 1] = {
                id = 'businesses:remove-module', label = 'Delete', icon = 'trash-2',
                variant = 'destructive', confirm = ('Delete "%s"?'):format(module.label),
            }
            moduleCards[#moduleCards + 1] = {
                id = tostring(index),
                label = module.label,
                description = module.moduleType,
                icon = module.moduleType == 'Zone' and 'scan' or 'blocks',
                badge = index,
                tone = index == state.moduleIndex and 'primary' or 'neutral',
                action = 'businesses:select-module',
                metadata = {
                    { label = 'Anchor', value = anchorLabel(module) },
                    { label = 'Access', value = module.public and 'Public' or 'Job restricted' },
                    { label = 'Interaction', value = S.moduleType[module.moduleType].interaction },
                },
                actions = moduleActions,
            }
        end

        local moduleBlocks = {
            {
                type = 'list', id = 'business-modules', layout = 'cards', searchable = true,
                pageSize = 8, searchPlaceholder = 'Search modules…', items = moduleCards,
                empty = 'No modules are configured. Add a perimeter first.',
            },
        }
        local selectedModule = business.modules[state.moduleIndex or 0]
        if selectedModule then
            moduleBlocks[#moduleBlocks + 1] = {
                type = 'details', title = ('Module %d · %s'):format(state.moduleIndex, selectedModule.label),
                columns = 2,
                items = {
                    { label = 'Type', value = selectedModule.moduleType, tone = 'primary' },
                    { label = 'Interaction', value = S.moduleType[selectedModule.moduleType].interaction },
                    { label = 'World anchor', value = anchorLabel(selectedModule) },
                    { label = 'Distance', value = selectedModule.distance or 'Default' },
                    { label = 'Access', value = selectedModule.public and 'Public' or business.job },
                    { label = 'Map blip', value = selectedModule.blip and 'Enabled' or 'None' },
                },
            }
        end

        local activity = {}
        for index, row in ipairs(state.logs or {}) do
            activity[#activity + 1] = {
                id = tostring(row.id or index),
                title = row.message or 'Business activity',
                timestamp = tostring(row.created_at or ''),
                tone = logTones[row.category] or 'neutral',
                icon = row.category == 'admin' and 'settings' or 'history',
                metadata = {
                    { label = 'Category', value = row.category or 'activity' },
                    { label = 'Amount', value = row.amount and money(row.amount) or '—' },
                },
            }
        end

        local tabs = {
            {
                id = 'overview', label = 'Overview', content = {
                    title = business.label, description = 'Live business status and ownership.',
                    actions = overviewActions,
                    blocks = {
                        { type = 'stats', items = {
                            { label = 'Balance', value = state.balance ~= nil and money(state.balance) or 'Unavailable',
                                description = state.balanceError, icon = 'wallet', tone = state.balance ~= nil and 'success' or 'warning' },
                            { label = 'Modules', value = #business.modules, icon = 'blocks', tone = 'primary' },
                            { label = 'Staff present', value = Client.staff[business.id] or 0, icon = 'users' },
                        } },
                        { type = 'details', title = 'Business details', columns = 2, items = {
                            { label = 'Business id', value = business.id },
                            { label = 'Job', value = business.job },
                            { label = 'Revision', value = business.rev or 'Pending' },
                            { label = 'Management', value = isAdmin and 'Administrator' or 'Job boss' },
                        } },
                    },
                },
            },
            {
                id = 'activity', label = 'Activity', badge = #activity, content = {
                    title = 'Recent activity', description = state.logsError,
                    blocks = { { type = 'timeline', title = 'Audit trail', items = activity,
                        empty = state.logsError or 'Nothing has happened here yet.' } },
                },
            },
        }
        if isAdmin then
            table.insert(tabs, 2, {
                id = 'modules', label = 'Modules', badge = #moduleCards, content = {
                    title = 'Module overview',
                    description = 'World editors close this console and reopen it on the same business and module.',
                    actions = {
                        {
                            id = 'businesses:add-module', label = 'Add module', icon = 'plus',
                            variant = 'primary', closeBeforeAction = true,
                        },
                    },
                    blocks = moduleBlocks,
                },
            })
            for offset, tab in ipairs(workspaceTabs(state, business)) do
                table.insert(tabs, 2 + offset, tab)
            end
            tabs[#tabs + 1] = {
                id = 'debug', label = 'Debug', icon = 'bug', content = {
                    title = 'Diagnostics',
                    description = 'Inspect live state, copy data for support, or show local world outlines.',
                    actions = {
                        { id = 'businesses:toggle-debug', label = Client.debug and 'Hide world debug' or 'Show world debug',
                            icon = 'bug', variant = Client.debug and 'secondary' or 'outline' },
                        { id = 'businesses:copy-business-data', label = 'Copy business data', icon = 'copy', variant = 'outline' },
                        { id = 'businesses:copy-module-data', label = 'Copy selected module', icon = 'copy', variant = 'outline',
                            disabled = not selectedModule },
                    },
                    blocks = {
                        { type = 'stats', items = {
                            { label = 'Live revision', value = business.rev or 'Pending', icon = 'git-commit', tone = 'primary' },
                            { label = 'Modules', value = #business.modules, icon = 'blocks' },
                            { label = 'World debug', value = Client.debug and 'On' or 'Off', icon = 'bug',
                                tone = Client.debug and 'warning' or 'neutral', description = 'Only visible on your client.' },
                        } },
                        { type = 'details', title = 'Selected module', columns = 2, items = {
                            { label = 'Selection', value = selectedModule and ('#%d · %s'):format(state.moduleIndex, selectedModule.label) or 'None' },
                            { label = 'Anchor', value = selectedModule and anchorLabel(selectedModule) or '—' },
                            { label = 'Interaction', value = selectedModule and S.moduleType[selectedModule.moduleType].interaction or '—' },
                            { label = 'Access', value = selectedModule and (selectedModule.public and 'Public' or business.job) or '—' },
                        } },
                        { type = 'text', title = 'Editing safely', text = 'Edit data changes a module in place and validates it before it goes live. Rebuild is for changing its placement. Copy buttons include public module data for backups or support; webhook URLs are omitted.' },
                    },
                },
            }
        end

        navigation[#navigation + 1] = {
            id = 'management', label = business.label, description = business.job,
            icon = 'layout-dashboard', defaultTab = state.moduleIndex and 'modules' or 'overview', tabs = tabs,
        }
    end

    return {
        id = APP_ID,
        title = 'Job Creator',
        description = business and business.label or 'Live business directory',
        icon = 'building-2',
        width = 1200,
        height = 800,
        navigation = navigation,
        footer = 'Data, permissions, and mutations are validated by the kora_jobcreator server.',
    }
end

---@param state table
---@return table update
appUpdate = function(state)
    local definition = appDefinition(state)
    return {
        title = definition.title,
        description = definition.description,
        navigation = definition.navigation,
        footer = definition.footer,
    }
end

---@param state table
---@param businessId string
---@param index? integer
---@param moduleType? string
local function launchModuleEditor(state, businessId, index, moduleType)
    CreateThread(function()
        local business = Client.definitions[businessId]
        if not business then
            Client.notify('That business no longer exists.', 'error')
            state.businessId, state.moduleIndex = nil, nil
            return openManagement(state, 'businesses')
        end

        local previousRev = business.rev
        local saved, position = editModule(business, index, moduleType)
        if saved then
            awaitBusiness(businessId, previousRev)
            state.moduleIndex = position or index
        else
            state.moduleIndex = index
        end
        state.businessId = businessId
        loadBusinessSummary(state)
        openManagement(state, 'management', 'modules')
    end)
end

---@param state table
---@param values table
local function createBusinessAndResume(state, values)
    CreateThread(function()
        local businessId, err = Kora.callback.trigger('kora_jobcreator:server:createBusiness', values)
        if not businessId then
            Client.notify(err or 'Could not create that business.', 'error')
            return openManagement(state, 'businesses')
        end

        local business = awaitBusiness(businessId)
        if not business then
            Client.notify('Business saved, but its live definition has not arrived yet.', 'warning')
            return openManagement(state, 'businesses')
        end

        state.businessId, state.moduleIndex = businessId, nil
        Client.notify('Business created. Add its perimeter next.', 'success')
        local previousRev = business.rev
        local saved, position = editModule(business)
        if saved then
            awaitBusiness(businessId, previousRev)
            state.moduleIndex = position
        end
        loadBusinessSummary(state)
        openManagement(state, 'management', 'modules')
    end)
end

---@param state table
---@return function
local function actionHandler(state)
    return function(actionId, context)
        local itemId = context and context.itemId
        local values = type(context and context.value) == 'table' and context.value or {}

        if actionId == 'businesses:select' then
            local business = itemId and Client.definitions[itemId]
            if not business or not (isAdmin or Client.isBoss(business)) then
                return { notice = { tone = 'destructive', message = 'That business is no longer available.' } }
            end
            state.businessId, state.moduleIndex = business.id, nil
            loadBusinessSummary(state)
            return { update = appUpdate(state), navigate = { viewId = 'management', tabId = 'overview' } }
        end

        if actionId == 'businesses:create' then
            createBusinessAndResume(state, { label = values.label, job = values.job })
            return
        end

        local business = state.businessId and Client.definitions[state.businessId]
        if not business or not (isAdmin or Client.isBoss(business)) then
            return { notice = { tone = 'destructive', message = 'That business is no longer available.' } }
        end

        if isAdmin then
            local result, handled = workspaceAction(state, business, actionId, itemId, values)
            if handled then return result end
        end

        if actionId == 'businesses:refresh' then
            loadBusinessSummary(state)
            return { update = appUpdate(state), notice = { tone = 'success', message = 'Business data refreshed.' } }
        elseif actionId == 'businesses:select-module' then
            local index = math.floor(tonumber(itemId) or 0)
            if not business.modules[index] then
                return { notice = { tone = 'destructive', message = 'That module no longer exists.' } }
            end
            state.moduleIndex = index
            return { update = appUpdate(state), navigate = { viewId = 'management', tabId = 'modules', replace = true } }
        elseif actionId == 'businesses:add-module' then
            launchModuleEditor(state, business.id)
            return
        elseif isAdmin and (actionId == 'tills:create' or actionId == 'stashes:create') then
            launchModuleEditor(state, business.id, nil, actionId == 'tills:create' and 'POS' or 'Stash')
            return
        elseif actionId == 'businesses:edit-module' then
            local index = math.floor(tonumber(itemId) or 0)
            local module = business.modules[index]
            if not module then error('That module no longer exists.') end
            launchModuleEditor(state, business.id, index, module.moduleType)
            return
        elseif actionId == 'businesses:edit-module-data' then
            local index = math.floor(tonumber(itemId) or 0)
            if not business.modules[index] then
                return { notice = { tone = 'destructive', message = 'That module no longer exists.' } }
            end
            CreateThread(function()
                local previousRev = business.rev
                local saved = editModuleData(business, index)
                if saved then awaitBusiness(business.id, previousRev) end
                state.businessId, state.moduleIndex = business.id, index
                loadBusinessSummary(state)
                openManagement(state, 'management', 'modules')
            end)
            return
        elseif actionId == 'businesses:toggle-debug' then
            Client.setDebug(not Client.debug)
            return { update = appUpdate(state), notice = { tone = 'success', message = Client.debug and 'Local world debug enabled.' or 'Local world debug hidden.' } }
        elseif actionId == 'businesses:copy-business-data' then
            Kora.nui.copyToClipboard(json.encode(business))
            return { notice = { tone = 'success', message = 'Business data copied to your clipboard.' } }
        elseif actionId == 'businesses:copy-module-data' then
            local module = business.modules[state.moduleIndex or 0]
            if not module then return { notice = { tone = 'warning', message = 'Select a module to copy its data.' } } end
            Kora.nui.copyToClipboard(json.encode(module))
            return { notice = { tone = 'success', message = 'Module data copied to your clipboard.' } }
        elseif actionId == 'businesses:remove-module' then
            local index = math.floor(tonumber(itemId) or 0)
            if not business.modules[index] then
                return { notice = { tone = 'destructive', message = 'That module no longer exists.' } }
            end
            local previousRev = business.rev
            local ok, err = Kora.callback.trigger('kora_jobcreator:server:removeModule', business.id, index)
            if not ok then return { notice = { tone = 'destructive', message = err or 'Could not delete that module.' } } end
            awaitBusiness(business.id, previousRev)
            state.moduleIndex = nil
            loadBusinessSummary(state)
            return { update = appUpdate(state), notice = { tone = 'success', message = 'Module deleted.' } }
        elseif actionId == 'businesses:edit' then
            local previousRev = business.rev
            local ok, err = Kora.callback.trigger('kora_jobcreator:server:editBusiness', business.id, {
                label = values.label, job = values.job,
            })
            if not ok then return { notice = { tone = 'destructive', message = err or 'That change was rejected.' } } end
            awaitBusiness(business.id, previousRev)
            loadBusinessSummary(state)
            return { update = appUpdate(state), notice = { tone = 'success', message = 'Business updated.' } }
        elseif actionId == 'businesses:delete' then
            local ok, err = Kora.callback.trigger('kora_jobcreator:server:deleteBusiness', business.id)
            if not ok then return { notice = { tone = 'destructive', message = err or 'Could not delete that business.' } } end
            state.businessId, state.moduleIndex, state.balance, state.logs = nil, nil, nil, {}
            return {
                update = appUpdate(state), navigate = { viewId = 'businesses', replace = true },
                notice = { tone = 'success', message = 'Business deleted.' },
            }
        end

        error('That business action is no longer available.')
    end
end

---@param state table
---@param viewId? string
---@param tabId? string
openManagement = function(state, viewId, tabId)
    local definition = appDefinition(state)
    definition.onAction = actionHandler(state)
    Kora.nui.registerApp(definition)
    currentState = state
    Kora.nui.openApp(APP_ID, { viewId = viewId, tabId = tabId })
    if currentState == state then currentState = nil end
end

---Refreshes an open console after the replicated business or staff snapshots
---change. It deliberately does not call the server from a net-event handler;
---the explicit Refresh action owns balance/log fetching.
---@return boolean updated
function Creator.refresh()
    if not currentState or not Kora.nui.isAppOpen(APP_ID) then return false end
    local business = currentState.businessId and Client.definitions[currentState.businessId]
    if currentState.businessId and (not business or not (isAdmin or Client.isBoss(business))) then
        currentState.businessId, currentState.moduleIndex = nil, nil
    elseif business and currentState.moduleIndex and not business.modules[currentState.moduleIndex] then
        currentState.moduleIndex = nil
    end
    return Kora.nui.updateApp(APP_ID, appUpdate(currentState))
end

function Creator.open()
    if Kora.nui.isAppOpen(APP_ID) then return end

    local businesses = manageableBusinesses()
    if not isAdmin and #businesses == 0 then
        return Client.notify('You do not manage any business.', 'error')
    end

    CreateThread(function()
        local jobs = {}
        if isAdmin then
            local result, err = Kora.callback.trigger('kora_jobcreator:server:jobs')
            if type(result) == 'table' then jobs = result
            elseif err then Client.notify(err, 'error') end
        end
        local state = { jobs = jobs, logs = {} }
        openManagement(state, 'businesses')
    end)
end

---@param value boolean
function Creator.setAdmin(value)
    isAdmin = value == true
    Creator.refresh()
end

RegisterCommand(Config.command, function() Creator.open() end, false)
