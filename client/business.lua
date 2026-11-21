-- The client half of a business: zones, blips, props and target options built
-- from the replicated definition.
--
-- A business owns two scopes. The STATIC scope holds its perimeter and map
-- blips and exists for as long as the business does. The DYNAMIC scope holds
-- everything you can actually interact with -- tills, stashes, benches, props --
-- and is built when the player walks into the perimeter and torn down when they
-- leave. A server with fifty businesses therefore holds fifty zones, not fifty
-- businesses' worth of props and target registrations.
--
-- A business with no perimeter has nothing to trigger that, so all of its
-- modules live in the static scope instead.

KoraJobCreator = KoraJobCreator or {}

local S = KoraJobCreator.schema
local Client = KoraJobCreator.client

local Business = {}
KoraJobCreator.Business = Business
local openCraftingMenu

-- All player-facing interactions are registered through kora_target.
local target = exports.kora_target

---@class KoraBossMenuClientExports
---@field openBossMenu fun(self: KoraBossMenuClientExports)

local function newScope()
    return { zones = {}, blips = {}, entities = {}, targets = {} }
end

---@param scope table
local function clearScope(scope)
    for _, zone in ipairs(scope.zones) do pcall(zone.remove) end
    for _, blip in ipairs(scope.blips) do Kora.blips.remove(blip) end
    for _, registration in ipairs(scope.targets) do
        if registration.kind == 'entity' then
            target:removeEntity(registration.entity, registration.id)
        else
            target:removeZone(registration.id)
        end
    end
    -- Entities last: a target registration still points at them.
    for _, entity in ipairs(scope.entities) do Kora.entities.remove(entity) end
    scope.zones, scope.blips, scope.entities, scope.targets = {}, {}, {}, {}
end

---@param name string
---@return integer
local function itemCount(name)
    -- An array path, not a dotted string -- see Client.job().
    local items = exports.kora_core:getPlayerData({ 'items' }) or {}
    local total = 0
    for _, item in pairs(items) do
        if item and item.name == name then total = total + (item.amount or 0) end
    end
    return total
end

---@param name string
---@return string
local function itemLabel(name)
    local definition = Kora.shared.get('items', name)
    return (definition and definition.label) or name
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

---@param definition table
---@return table
function Business.create(definition)
    local business = {
        id = definition.id, label = definition.label, job = definition.job,
        definition = definition,
        hasPerimeter = S.hasPerimeter(definition),
        static = newScope(), dynamic = newScope(), inside = false,
    }
    Business.build(business, business.static, true)
    return business
end

---@param stopping? boolean Skip the server round-trip (the resource is stopping).
function Business.destroy(business, stopping)
    if business.inside then Business.leave(business, stopping) end
    clearScope(business.dynamic)
    clearScope(business.static)
end

---@param scope table
---@param startup boolean
function Business.build(business, scope, startup)
    for index, module in ipairs(business.definition.modules) do
        if S.isStartupModule(business.definition, module) == startup then
            local ok, err = pcall(Business.setup, business, scope, index, module)
            if not ok then
                Kora.logging.warn('business.module_setup_failed', 'Business module setup failed', { businessId = business.id, moduleIndex = index, moduleType = module.moduleType, error = tostring(err) })
            end
        end
    end
end

---Entering yields -- props stream in and the server is told who arrived -- and
---`onEnter` runs on kora_lib's shared zone tick thread, which every zone in every
---resource shares. So the flag flips synchronously (that is what makes a second
---`onEnter` a no-op) and the actual work is handed to a thread of our own.
---
---`generation` is what makes that safe: walking back out while the props are
---still streaming bumps it, and the build thread cleans up after itself instead
---of leaving orphaned entities and targets behind a player who already left.
function Business.enter(business)
    if business.inside then return end
    business.inside = true
    business.generation = (business.generation or 0) + 1

    local generation = business.generation
    CreateThread(function()
        Business.build(business, business.dynamic, false)
        if business.generation ~= generation then return clearScope(business.dynamic) end

        if Client.worksFor(business) then
            if business.controlDuty and Config.duty.enabled then Business.setDuty(business, true) end
            -- Presence means on-duty staff. Auto-duty therefore commits first;
            -- the following callback is independently revalidated server-side.
            Kora.callback.trigger('kora_jobcreator:server:enter', business.id)
        end
    end)
end

---@param teardownOnly? boolean Skip the server round-trip (resource stopping).
function Business.leave(business, teardownOnly)
    if not business.inside then return end
    business.inside = false
    business.generation = (business.generation or 0) + 1
    clearScope(business.dynamic)
    if teardownOnly then return end

    if Client.worksFor(business) then
        CreateThread(function()
            Kora.callback.trigger('kora_jobcreator:server:leave', business.id)
            if business.controlDuty and Config.duty.enabled then Business.setDuty(business, false) end
        end)
    end
end

---@param onDuty boolean
function Business.setDuty(business, onDuty)
    local job = Client.job()
    if job.onduty == onDuty then return end

    -- Leaving in a company vehicle is going out on a job, not clocking off.
    if not onDuty and Config.duty.keepDutyInJobVehicle then
        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        if vehicle ~= 0 then
            local plate = GetVehicleNumberPlateText(vehicle) or ''
            if plate:sub(1, 3):lower() == business.job:sub(1, 3):lower() then return end
        end
    end

    Kora.callback.trigger('kora_jobcreator:server:setDuty', business.id, onDuty)
end

---@param scope table
---@param module table
---@return integer[] entities
function Business.spawn(business, scope, module)
    local entities = {}
    for _, coords in ipairs(module.coords) do
        if module.model.existing then
            -- The mapper already placed this prop; adopt whatever is standing
            -- there rather than spawning a second copy on top of it.
            local existing = GetClosestObjectOfType(coords.x, coords.y, coords.z, 1.5, joaat(module.model.model), false, false, false)
            if existing ~= 0 then entities[#entities + 1] = existing end
        else
            local entity = Kora.entities.create(module.model.model, Client.vec4(coords), {
                preset = 'static',
                freeze = module.model.freeze ~= false,
            })
            if entity then
                scope.entities[#scope.entities + 1] = entity
                entities[#entities + 1] = entity
                if module.model.anim and module.model.modelType == 'ped' then
                    Kora.anim.play(entity, module.model.anim.dict, module.model.anim.clip, { flag = module.model.anim.flag })
                end
            end
        end
    end
    return entities
end

---Wraps every option's `canInteract` with the module's job gate, then registers
---them against whichever anchor the module has.
---@param scope table
---@param module table
---@param index integer
---@param entities integer[]
---@param options table[]
function Business.attach(business, scope, index, module, entities, options)
    local job = (not module.public) and business.job or nil

    for _, option in ipairs(options) do
        option.distance = option.distance or module.distance

        -- kora_target invokes a single-candidate onSelect on its own tick thread.
        -- Nearly everything here yields (a callback, a dialog, a progress bar),
        -- which would stall targeting for as long as the menu is open -- and
        -- Kora.callback.trigger has to be inside a coroutine anyway.
        local select_ = option.onSelect
        local function runSelection(...)
            local args = table.pack(...)
            CreateThread(function() select_(table.unpack(args, 1, args.n)) end)
        end
        -- Target selections may yield, so hand the work to its own thread.
        option.onSelect = runSelection

        local base, ignoreLock = option.canInteract, option.ignoreJobLock
        option.ignoreJobLock = nil
        if job and not ignoreLock then
            option.canInteract = function(entity, distance, data)
                if Client.job().name ~= job then return false end
                if base then return base(entity, distance, data) end
                return true
            end
        end
    end

    if #entities > 0 then
        for _, entity in ipairs(entities) do
            local id = target:addEntity(entity, options)
            if id then scope.targets[#scope.targets + 1] = { kind = 'entity', entity = entity, id = id } end
        end
        return
    end

    local id
    if module.zoneType == 'sphere' then
        id = target:addSphereZone({
            coords = Client.vec3(module.coords), radius = module.radius,
            options = options,
            distance = module.distance, debug = Client.debug,
        })
    elseif module.zoneType == 'box' then
        id = target:addBoxZone({
            coords = Client.vec3(module.coords),
            size = vector3(module.size.x, module.size.y, module.size.z),
            rotation = module.rotation, options = options,
            distance = module.distance, debug = Client.debug,
        })
    elseif module.zoneType == 'poly' then
        local points = {}
        for _, point in ipairs(module.points) do points[#points + 1] = Client.vec3(point) end
        id = target:addPolyZone({
            points = points, thickness = module.thickness,
            options = options, distance = module.distance, debug = Client.debug,
        })
    end
    if id then
        scope.targets[#scope.targets + 1] = { kind = 'zone', id = id }
    end
end

---Adds a target circle for category-owned crafting coordinates.
---@param business table
---@param scope table
---@param index integer
---@param module table
---@param category table
---@param locationIndex integer
function Business.attachCraftingLocation(business, scope, index, module, category, locationIndex)
    local location = category.locations[locationIndex]
    local coords = location and (location.coords or location)
    if not coords then return end
    local options = { {
        label = category.label,
        icon = 'Hammer',
        distance = module.distance,
        onSelect = function() openCraftingMenu(business, index, module, category) end,
    } }

    for _, option in ipairs(options) do
        local select_ = option.onSelect
        option.onSelect = function(...)
            local args = table.pack(...)
            CreateThread(function() select_(table.unpack(args, 1, args.n)) end)
        end
        option.canInteract = function() return Client.job().name == business.job end
    end

    local id = target:addSphereZone({
        coords = Client.vec3(coords), radius = module.distance, options = options,
        distance = module.distance, debug = Client.debug,
    })
    if id then scope.targets[#scope.targets + 1] = { kind = 'zone', id = id } end
end

---@param business table
---@param scope table
---@param module table
---@param category table
---@param locationIndex integer
function Business.attachStoreLocation(business, scope, module, category, locationIndex)
    local location = category.locations[locationIndex]
    local coords = location and (location.coords or location)
    if not coords then return end

    local function runInThread(callback)
        return function(...)
            local args = table.pack(...)
            CreateThread(function() callback(table.unpack(args, 1, args.n)) end)
        end
    end
    local options = { {
        label = ('Browse %s'):format(category.label),
        icon = 'ShoppingCart',
        canInteract = function() return Client.job().name == business.job end,
        onSelect = runInThread(function()
            local catalog, err = Kora.callback.trigger('kora_jobcreator:server:storeCatalog', business.id, category.id)
            if type(catalog) ~= 'table' then return Client.notify(err or 'This store is unavailable.', 'error') end
            Business.openStoreApp(business, category, catalog)
        end),
    } }
    local distance = module.distance or 2.0
    local id = target:addSphereZone({
        coords = Client.vec3(coords), radius = distance, options = options,
        distance = distance, debug = Client.debug,
    })
    if id then scope.targets[#scope.targets + 1] = { kind = 'zone', id = id } end
end

function Business.openStoreApp(business, category, catalog)
    local appId = ('kora_jobcreator:store:%s:%s'):format(business.id, category.id)
    local function navigation(data)
        local cards = {}
        for _, item in ipairs(data.items or {}) do
            cards[#cards + 1] = {
                id = item.name,
                label = item.label or item.name,
                description = ('$%d each'):format(item.price or 0),
                image = itemImage(item.name),
                actions = { {
                    id = 'store:purchase', label = 'Pick up', icon = 'shopping-cart', variant = 'primary',
                    fields = { {
                        id = 'amount', label = 'Quantity', type = 'number', required = true,
                        min = 1, max = 1000000, default = 1,
                    } },
                } },
            }
        end
        return { {
            id = 'shop', label = data.label or 'Store', icon = 'store', content = {
                title = data.label or 'Store',
                description = 'Choose an ingredient, enter a quantity, and pick it up.',
                blocks = { {
                    type = 'list', id = 'store-purchase-items', title = 'Available items',
                    layout = 'cards', cardStyle = 'compact', columns = 1, searchable = true,
                    pageSize = 30, searchPlaceholder = 'Search store items…', items = cards,
                    empty = 'No ingredients are configured for this store.',
                } },
            },
        } }
    end

    Kora.nui.registerApp({
        id = appId, title = catalog.label or category.label, description = 'Employee ingredient pickup.',
        icon = 'store', layout = 'compact', placement = 'right', width = 520,
        navigation = navigation(catalog),
        onAction = function(actionId, context)
            if actionId ~= 'store:purchase' then return end
            local itemName = tostring(context and context.itemId or '')
            local values = type(context and context.value) == 'table' and context.value or {}
            local amount = tonumber(values.amount)
            if itemName == '' or not amount then return { notice = { tone = 'destructive', message = 'Enter a valid quantity.' } } end

            local ok, result = Kora.callback.trigger('kora_jobcreator:server:purchaseStoreItem', business.id, category.id, itemName, amount)
            if not ok then return { notice = { tone = 'destructive', message = result or 'Could not complete that purchase.' } } end
            local refreshed = Kora.callback.trigger('kora_jobcreator:server:storeCatalog', business.id, category.id)
            return {
                update = type(refreshed) == 'table' and { title = refreshed.label or category.label, navigation = navigation(refreshed) } or nil,
                notice = { tone = 'success', message = result or 'Pickup complete.' },
            }
        end,
    })
    Kora.nui.openApp(appId)
end

---@param scope table
---@param blip table
local function addBlip(scope, blip)
    local handle = Kora.blips.create(vector3(blip.coords.x, blip.coords.y, blip.coords.z), {
        sprite = blip.sprite, color = blip.color, scale = blip.scale, display = blip.display,
        shortRange = blip.shortRange, category = blip.category, name = blip.name,
        info = blip.info or {
            title = blip.name or blip.category or 'Business',
            rows = {
                { kind = 'wrappedText', value = 'Business services are available at this location.' },
            },
        },
    })
    if handle then scope.blips[#scope.blips + 1] = handle end
end

local builders = {}

function Business.setup(business, scope, index, module)
    local builder = builders[module.moduleType]
    if not builder then return end

    local entities = module.model and Business.spawn(business, scope, module) or {}
    if module.blip then addBlip(scope, module.blip) end

    local options = builder(business, scope, index, module, entities)
    if options and #options > 0 then Business.attach(business, scope, index, module, entities, options) end
end

builders.Zone = function(business, scope, _, module)
    business.controlDuty = module.controlDuty
    local opts = {
        onEnter = function() Business.enter(business) end,
        onExit = function() Business.leave(business) end,
        debug = Client.debug,
    }
    if module.zoneType == 'sphere' then
        opts.coords, opts.radius = Client.vec3(module.coords), module.radius
    elseif module.zoneType == 'box' then
        opts.coords = Client.vec3(module.coords)
        opts.size = vector3(module.size.x, module.size.y, module.size.z)
        opts.rotation = module.rotation
    else
        local points = {}
        for _, point in ipairs(module.points) do points[#points + 1] = Client.vec3(point) end
        opts.points, opts.thickness = points, module.thickness
    end
    scope.zones[#scope.zones + 1] = Kora.zones[module.zoneType](opts)
end

builders.Blip = function(_, scope, _, module)
    addBlip(scope, {
        coords = module.coords, sprite = module.sprite, color = module.color, display = module.display,
        scale = module.scale, shortRange = module.shortRange,
        category = module.category, name = module.name,
    })
end

builders.StaticEntity = function() return nil end

builders.BossMenu = function(business, _, _, module)
    return { {
        label = module.label,
        icon = module.icon or 'Briefcase',
        canInteract = function() return Client.isBoss(business) end,
        onSelect = function()
            if GetResourceState('kora_bossmenu') ~= 'started' then
                return Client.notify('The boss menu is unavailable.', 'error')
            end
            ---@type KoraBossMenuClientExports
            local bossMenu = exports.kora_bossmenu
            bossMenu:openBossMenu()
        end,
    } }
end

builders.Stash = function(_, _, _, module)
    return { {
        label = module.label,
        icon = module.icon or 'Archive',
        onSelect = function()
            local ok, err = Kora.callback.trigger('kora_jobcreator:server:openStash', module.id)
            if not ok then Client.notify(err or 'You cannot open that.', 'error') end
        end,
    } }
end

builders.POS = function(business, _, _, module)
    local options = {}

    if module.closedShop then
        options[#options + 1] = {
            label = 'Browse shop',
            icon = 'ShoppingCart',
            canInteract = function()
                if Client.worksFor(business) then return true end
                return (Client.staff[business.id] or 0) == 0
            end,
            onSelect = function()
                local ok, err = Kora.callback.trigger('kora_jobcreator:server:openShop', module.id)
                if not ok then Client.notify(err or 'You cannot use this shop.', 'error') end
            end,
        }

        options[#options + 1] = {
            label = 'Restock',
            icon = 'PackagePlus',
            canInteract = function() return Client.worksFor(business) end,
            onSelect = function()
                local ok, err = Kora.callback.trigger('kora_jobcreator:server:openStock', module.id)
                if not ok then Client.notify(err or 'You cannot restock this shop.', 'error') end
            end,
        }
    end

    -- These actions gate themselves so a public closed shop does not expose
    -- staff controls to customers.
    options[#options + 1] = {
        label = 'Set prices',
        icon = 'DollarSign',
        canInteract = function() return Client.isBoss(business) end,
        onSelect = function() KoraJobCreator.openPriceEditor(module.id) end,
    }

    options[#options + 1] = {
        label = 'Take a payment',
        icon = 'CreditCard',
        canInteract = function() return Client.worksFor(business) end,
        onSelect = function() KoraJobCreator.takePayment(nil, business.id, module.id) end,
    }

    if module.panicButton then
        options[#options + 1] = {
            label = 'Panic button',
            icon = 'Siren',
            canInteract = function() return Client.worksFor(business) end,
            onSelect = function()
                local ok, err = Kora.callback.trigger('kora_jobcreator:server:panic', business.id, module.id)
                Client.notify(ok and 'Silent alarm sent.' or (err or 'The alarm did not go through.'), ok and 'success' or 'error')
            end,
        }
    end

    return options
end

---Renders one bench's recipe list, with live ingredient counts.
---@param business table
---@param index integer
---@param module table
openCraftingMenu = function(business, index, module, category)
    local recipes, recipesErr = Kora.callback.trigger('kora_jobcreator:server:benchRecipes', business.id, index, category.id)
    if type(recipes) ~= 'table' then return Client.notify(recipesErr or 'Could not load this business’s recipes.', 'error') end
    local recipeMap = {}
    for _, recipe in ipairs(recipes) do if recipe.id ~= nil then recipeMap[tostring(recipe.id)] = recipe end end
    local items = {}
    for _, recipeId in ipairs(category.recipes or {}) do
        local recipe = recipeMap[tostring(recipeId)]
        if recipe then
            local parts, ready = {}, true
            for _, ingredient in ipairs(recipe.ingredients or {}) do
                local name = ingredient.item or ingredient.name
                local needed = math.max(math.floor(tonumber(ingredient.amount or ingredient.count) or 1), 1)
                local have = itemCount(name)
                if have < needed then ready = false end
                parts[#parts + 1] = ('%s %d/%d'):format(itemLabel(name), have, needed)
            end
            items[#items + 1] = {
                id = tostring(recipeId),
                label = recipe.label or tostring(recipeId),
                description = #parts > 0 and table.concat(parts, ', ') or 'No ingredients required',
                image = recipe.output and recipe.output.item and itemImage(recipe.output.item),
                disabled = not ready,
            }
        end
    end

    if #items == 0 then return Client.notify('There is nothing to make here.', 'error') end

    local appId = ('kora_jobcreator:crafting:%s:%s:%s'):format(business.id, index, category.id)
    for _, item in ipairs(items) do item.actions = { { id = 'craft:' .. item.id, label = 'Craft', icon = 'hammer', closeBeforeAction = true } } end
    Kora.nui.registerApp({
        id = appId, title = category.label, description = ('Choose a %s recipe.'):format(category.label), icon = 'hammer',
        layout = 'compact', placement = 'right', width = 520, height = 700,
        navigation = { { id = 'recipes', label = category.label, icon = 'list', content = {
            title = category.label, description = 'Ingredient counts update each time you open the bench.',
            blocks = { {
                type = 'list', id = 'crafting-recipes', layout = 'cards', cardStyle = 'compact',
                columns = 1, imageFit = 'contain', items = items, empty = 'There is nothing to make here.',
            } },
        } } },
        onAction = function(actionId)
            local recipeId = actionId:match('^craft:(.+)$')
            local recipe = recipeId and recipeMap[tostring(tonumber(recipeId) or recipeId)]
            if not recipe then return end
            if recipe.time and recipe.time > 0 then
                local progress = {
                    label = recipe.progressLabel or ('Making %s'):format(recipe.label or recipeId),
                    duration = math.floor(recipe.time), canCancel = true,
                    disable = { move = true, combat = true, car = true },
                }
                local animation = recipe.animation
                if animation and animation.type == 'emote' then
                    progress.emote = animation.name
                elseif animation and animation.type == 'animation' then
                    progress.anim = { dict = animation.dict, clip = animation.clip, flag = animation.flag }
                elseif recipe.anim then
                    progress.anim = recipe.anim
                end
                local completed = Kora.progressbar.start(progress)
                if not completed then return end
            end
            local ok, message = Kora.callback.trigger('kora_jobcreator:server:craft', business.id, index, category.id, tonumber(recipeId) or recipeId)
            Client.notify(message or (ok and 'Done.' or 'That did not work.'), ok and 'success' or 'error')
        end,
    })
    Kora.nui.openApp(appId)
end

builders.Crafting = function(business, scope, index, module)
    for _, category in pairs(module.crafters or {}) do
        for locationIndex in ipairs(category.locations or {}) do
            Business.attachCraftingLocation(business, scope, index, module, category, locationIndex)
        end
    end
end

builders.SalesItems = function(business, scope, _, module)
    for _, category in pairs(module.stores or {}) do
        category.id = category.id or S.slug(category.label)
        category.label = category.label or category.id
        for locationIndex in ipairs(category.locations or {}) do
            Business.attachStoreLocation(business, scope, module, category, locationIndex)
        end
    end
end
