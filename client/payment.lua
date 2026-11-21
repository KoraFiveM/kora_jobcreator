-- Itemized employee sales and the portable card machine.
--
-- The seller builds a cart from the business Sales Items list. The server owns
-- authorization, inventory, payment and payout; this client only renders the
-- catalog and collects the seller's prices and the buyer's consent/payment type.

KoraJobCreator = KoraJobCreator or {}

local Client = KoraJobCreator.client
local promptSequence = 0

local function nextAppId(prefix)
    promptSequence = promptSequence + 1
    return ('kora_jobcreator:%s:%d:%d'):format(prefix, GetGameTimer(), promptSequence)
end

local function openPrompt(title, description, fields, actionId, onAction)
    local appId = nextAppId('prompt')
    local pending, resolved = promise.new(), false
    local function resolve(value)
        if resolved then return end
        resolved = true
        pending:resolve(value)
    end

    Kora.nui.registerApp({
        id = appId, title = title, description = description, icon = 'briefcase', width = 640, height = 480,
        navigation = { { id = 'prompt', label = title, icon = 'pencil', content = {
            title = title,
            actions = { { id = actionId, label = 'Continue', icon = 'arrow-right', variant = 'primary', closeBeforeAction = true, fields = fields } },
            blocks = { { type = 'text', title = title, text = description or '' } },
        } } },
        onAction = function(selectedAction, context)
            if selectedAction ~= actionId then return end
            local values = type(context and context.value) == 'table' and context.value or {}
            resolve(onAction and onAction(values) or values)
        end,
    })
    Kora.nui.openApp(appId)

    CreateThread(function()
        while not resolved do
            Wait(100)
            if not Kora.nui.isAppOpen(appId) then resolve(nil) end
        end
    end)

    return Citizen.Await(pending)
end

local function getBusiness(businessId)
    if businessId then
        local business = Client.definitions[businessId]
        return business and Client.worksFor(business) and business or nil
    end

    local jobName = Client.job().name
    for _, business in pairs(Client.definitions) do
        if business.job == jobName then return business end
    end
end

local function inventoryCounts()
    local items = exports.kora_core:getPlayerData({ 'items' }) or {}
    local counts = {}
    for _, item in pairs(items) do
        if type(item) == 'table' and type(item.name) == 'string' then
            counts[item.name] = (counts[item.name] or 0) + (math.floor(tonumber(item.amount) or 0))
        end
    end
    return counts
end

local function itemDetails(name)
    local definition = Kora.shared.get('items', name)
    local image = definition and definition.image
    if type(image) == 'string' and image ~= '' and not image:match('^https?://') and not image:match('^nui://') then
        image = ('nui://kora_inventory/images/%s'):format(image)
    end
    return definition and definition.label or name, image
end

local function cartTotal(cart)
    local total = 0
    for _, entry in pairs(cart) do total = total + entry.amount * entry.unitPrice end
    return total
end

local function customerOptions(preselected)
    local ownIndex = PlayerId()
    local ownId = GetPlayerServerId(ownIndex)
    local options = { { value = tostring(ownId), label = ('%s (you)'):format(GetPlayerName(ownIndex) or 'You') } }
    local seen = { [ownId] = true }
    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= ownIndex then
            local serverId = GetPlayerServerId(playerIndex)
            if serverId and serverId > 0 and not seen[serverId] then
                seen[serverId] = true
                options[#options + 1] = {
                    value = tostring(serverId),
                    label = ('%s (%d)'):format(GetPlayerName(playerIndex) or 'Player', serverId),
                }
            end
        end
    end
    if preselected and not seen[preselected] then
        options[#options + 1] = { value = tostring(preselected), label = ('Player (%d)'):format(preselected) }
    end
    table.sort(options, function(a, b)
        if a.value == tostring(ownId) then return true end
        if b.value == tostring(ownId) then return false end
        return a.label:lower() < b.label:lower()
    end)
    return options, tostring(preselected or ownId)
end

local function cartRows(cart)
    local rows = {}
    for name, entry in pairs(cart) do
        local label, image = itemDetails(name)
        rows[#rows + 1] = {
            id = name,
            label = label,
            description = ('%d × $%d each = $%d'):format(entry.amount, entry.unitPrice, entry.amount * entry.unitPrice),
            image = image,
            actions = { { id = 'sale:remove', label = 'Remove', icon = 'trash-2', variant = 'outline' } },
        }
    end
    table.sort(rows, function(a, b) return a.label:lower() < b.label:lower() end)
    return rows
end

local function catalogRows(business, cart)
    local salesItems, seen = {}, {}
    for _, module in ipairs(business.modules or {}) do
        if module.moduleType == 'SalesItems' then
            for _, name in ipairs(module.items or {}) do
                if type(name) == 'string' and not seen[name] then
                    seen[name] = true
                    salesItems[#salesItems + 1] = name
                end
            end
            break
        end
    end

    local counts, rows = inventoryCounts(), {}
    for _, name in ipairs(salesItems) do
        local label, image = itemDetails(name)
        local onHand = counts[name] or 0
        local inSale = cart[name] and cart[name].amount or 0
        local available = math.max(onHand - inSale, 0)
        local fields = available > 0 and {
            { id = 'amount', label = 'Quantity', type = 'number', required = true, min = 1, max = available, default = 1 },
            { id = 'unitPrice', label = 'Price per item', type = 'number', required = true, min = 1,
                max = Config.payment.maxAmount, default = cart[name] and cart[name].unitPrice },
        } or nil
        rows[#rows + 1] = {
            id = name,
            label = label,
            description = inSale > 0 and ('On hand: %d · In sale: %d'):format(onHand, inSale) or ('On hand: %d'):format(onHand),
            image = image,
            actions = fields and { { id = 'sale:add', label = 'Add to sale', icon = 'plus', variant = 'primary', fields = fields } } or {},
        }
    end
    table.sort(rows, function(a, b) return a.label:lower() < b.label:lower() end)
    return rows
end

local function saleNavigation(business, cart, target)
    local total = cartTotal(cart)
    local actions = {}
    if total > 0 then
        local customers, selectedCustomer = customerOptions(target)
        actions[1] = {
            id = 'sale:charge', label = ('Charge customer · $%d'):format(total), icon = 'credit-card',
            variant = 'primary', closeBeforeAction = true, fields = {
                { id = 'targetId', label = 'Customer', type = 'select', required = true,
                    options = customers, default = selectedCustomer },
            },
        }
    end

    return { {
        id = 'sale', label = 'Sale', icon = 'shopping-cart', content = {
            title = 'Build a sale',
            description = ('Choose quantities and unit prices from %s Sales Items. Only items you carry can be sold.'):format(business.label),
            actions = actions,
            blocks = {
                { type = 'list', id = 'sale-cart', title = 'Items in this sale', layout = 'cards', columns = 3,
                    items = cartRows(cart), empty = 'Add items below to build the sale.' },
                { type = 'list', id = 'sale-catalog', title = 'Items you can sell', layout = 'cards', columns = 4,
                    searchable = true, pageSize = 24, searchPlaceholder = 'Search sales items…',
                    items = catalogRows(business, cart), empty = 'No items are selected on this business’s Sales Items page.' },
            },
        },
    } }
end

local function openSaleApp(business, cart, target, moduleId)
    local appId = nextAppId('sale')
    Kora.nui.registerApp({
        id = appId, title = ('Take payment · %s'):format(business.label), description = 'Create an itemized sale.',
        icon = 'shopping-cart', width = 1100, height = 800,
        navigation = saleNavigation(business, cart, target),
        onAction = function(actionId, context)
            local itemName = tostring(context and context.itemId or '')
            local values = type(context and context.value) == 'table' and context.value or {}
            if actionId == 'sale:add' then
                local amount, unitPrice = tonumber(values.amount), tonumber(values.unitPrice)
                local available = inventoryCounts()[itemName] or 0
                if not itemName or itemName == '' or not amount or amount % 1 ~= 0 or amount < 1 or amount > available then
                    return { notice = { tone = 'destructive', message = 'Enter a quantity you currently have.' } }
                end
                if not unitPrice or unitPrice % 1 ~= 0 or unitPrice < 1 or unitPrice > Config.payment.maxAmount then
                    return { notice = { tone = 'destructive', message = 'Enter a valid unit price.' } }
                end
                if cart[itemName] and cart[itemName].unitPrice ~= unitPrice then
                    return { notice = { tone = 'destructive', message = 'Remove this item first to change its unit price.' } }
                end
                local nextAmount = (cart[itemName] and cart[itemName].amount or 0) + amount
                if nextAmount > available then return { notice = { tone = 'destructive', message = 'You do not have that many to sell.' } } end
                cart[itemName] = { amount = nextAmount, unitPrice = unitPrice }
                if cartTotal(cart) > Config.payment.maxAmount then
                    cart[itemName].amount = cart[itemName].amount - amount
                    if cart[itemName].amount == 0 then cart[itemName] = nil end
                    return { notice = { tone = 'destructive', message = 'This sale exceeds the payment limit.' } }
                end
                return { update = { navigation = saleNavigation(business, cart, target) } }
            elseif actionId == 'sale:remove' then
                cart[itemName] = nil
                return { update = { navigation = saleNavigation(business, cart, target) } }
            elseif actionId == 'sale:charge' then
                local targetId = math.floor(tonumber(values.targetId) or 0)
                if targetId <= 0 then return { notice = { tone = 'destructive', message = 'Select a valid customer.' } } end
                local saleItems = {}
                for name, entry in pairs(cart) do
                    saleItems[#saleItems + 1] = { item = name, amount = entry.amount, unitPrice = entry.unitPrice }
                end
                local ok, err = Kora.callback.trigger(
                    'kora_jobcreator:server:requestPayment', targetId, business.id, moduleId or false, saleItems
                )
                if not ok then
                    Client.notify(err or 'The sale could not be completed.', 'error')
                    CreateThread(function() Wait(250) openSaleApp(business, cart, targetId, moduleId) end)
                    return
                end
                Client.notify('Sale paid and completed.', 'success')
            end
        end,
    })
    Kora.nui.openApp(appId)
end

local function openSaleApproval(request)
    local appId = nextAppId('approval')
    local pending, resolved = promise.new(), false
    local function resolve(value)
        if resolved then return end
        resolved = true
        pending:resolve(value)
    end

    local rows = {}
    for index, entry in ipairs(request.items or {}) do
        local localLabel, image = itemDetails(entry.item)
        rows[#rows + 1] = {
            id = tostring(index), label = entry.label or localLabel,
            description = ('%d × $%d = $%d'):format(entry.amount, entry.unitPrice, entry.amount * entry.unitPrice),
            image = image,
        }
    end
    Kora.nui.registerApp({
        id = appId, title = 'Payment approval', description = ('%s requests $%d'):format(request.business or 'Business', request.total or 0),
        icon = 'receipt', width = 760, height = 640,
        navigation = { { id = 'invoice', label = 'Invoice', icon = 'receipt', content = {
            title = 'Review this sale', description = 'Choose how to pay or decline the request.',
            actions = {
                { id = 'invoice:cash', label = 'Pay with cash', icon = 'banknote', variant = 'primary', closeBeforeAction = true },
                { id = 'invoice:card', label = 'Pay with card', icon = 'credit-card', variant = 'primary', closeBeforeAction = true },
                { id = 'invoice:decline', label = 'Decline', icon = 'x', variant = 'outline', closeBeforeAction = true },
            },
            blocks = {
                { type = 'list', id = 'payment-invoice', title = request.business or 'Business', layout = 'cards', items = rows },
                { type = 'text', title = 'Total due', text = ('$%d'):format(request.total or 0) },
            },
        } } },
        onAction = function(actionId)
            if actionId == 'invoice:cash' then resolve('cash')
            elseif actionId == 'invoice:card' then resolve('bank')
            elseif actionId == 'invoice:decline' then resolve(false) end
        end,
    })
    Kora.nui.openApp(appId)

    CreateThread(function()
        while not resolved do
            Wait(100)
            if not Kora.nui.isAppOpen(appId) then resolve(false) end
        end
    end)

    return Citizen.Await(pending)
end

---Asked when an employee restocks an item this till has no fixed price for.
Kora.callback.register('kora_jobcreator:client:setPrice', function(request)
    local values = openPrompt('Set a price', 'This price is remembered for future restocks of this item.', {
        { id = 'price', label = ('Price for %s'):format(request.label or request.item), type = 'number', required = true, min = 0, max = request.max, default = 0 },
    }, 'price:submit')
    return values and tonumber(values.price) or nil
end)

Kora.callback.register('kora_jobcreator:client:approveSale', function(request)
    return openSaleApproval(request)
end)

---@param target? integer Server id; preselects the buyer when called from a player target.
---@param businessId? string Exact business id when called from a business till.
---@param moduleId? string POS id to require seller proximity; nil for the portable card machine.
function KoraJobCreator.takePayment(target, businessId, moduleId)
    local business = getBusiness(businessId)
    if not business then return Client.notify('You are not working for this business.', 'error') end

    local cart = {}
    if #catalogRows(business, cart) == 0 then
        return Client.notify('No Sales Items are configured for this business.', 'error')
    end
    openSaleApp(business, cart, target, moduleId)
end

---The portable card machine works anywhere and preselects the targeted buyer.
CreateThread(function()
    exports.kora_target:addGlobalType('player', { {
        label = 'Take a payment',
        icon = 'CreditCard',
        distance = Config.payment.distance,
        canInteract = function(entity)
            if not exports.kora_inventory:HasItem(Config.payment.item) then return false end
            return NetworkGetPlayerIndexFromPed(entity) ~= -1
        end,
        onSelect = function(entity)
            local index = NetworkGetPlayerIndexFromPed(entity)
            if index == -1 then return end
            KoraJobCreator.takePayment(GetPlayerServerId(index))
        end,
    } }, Config.payment.distance)
end)
