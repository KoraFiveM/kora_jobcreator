-- Employee item sales. The seller builds an itemized cart from Sales Items,
-- then the customer approves the exact items and chooses cash or card.
-- Inventory and money are revalidated and mutated server-side only.

KoraJobCreator = KoraJobCreator or {}

local State = KoraJobCreator.state
local Logs = KoraJobCreator.logs
local Pos = KoraJobCreator.pos

local Payment = {}
KoraJobCreator.payment = Payment

---@type table<integer, true> employees with a sale already in flight
local inFlight = {}
---@type table<integer, true> customers currently reviewing a sale
local pendingCustomers = {}

AddEventHandler('playerDropped', function()
    inFlight[source] = nil
    pendingCustomers[source] = nil
end)

---@param src integer
---@param businessId? string
---@return table|nil
local function businessFor(src, businessId)
    local job = State.playerJob(src)
    if not job or not job.name then return nil end
    if businessId then
        local business = State.get(businessId)
        return business and business.job == job.name and business or nil
    end
    for _, business in pairs(State.businesses) do
        if business.job == job.name then return business end
    end
end

local function paymentModule(business, moduleId)
    if not moduleId then return nil end
    for _, module in ipairs(business.modules or {}) do
        if module.moduleType == 'POS' and module.id == moduleId and not module.isStore then return module end
    end
end

local function hasCardMachine(src)
    local data = exports.kora_core:getPlayerData(src)
    if type(data) ~= 'table' or type(data.items) ~= 'table' then return false end
    for _, item in pairs(data.items) do
        if type(item) == 'table' and item.name == Config.payment.item and (tonumber(item.amount) or 0) > 0 then return true end
    end
    return false
end

---@param business table
---@return table<string, true>
local function salesCatalog(business)
    local allowed = {}
    for _, module in ipairs(business.modules or {}) do
        if module.moduleType == 'SalesItems' then
            for _, name in ipairs(module.items or {}) do
                if type(name) == 'string' then allowed[name:lower()] = true end
            end
            for _, category in pairs(module.stores or {}) do
                for _, name in ipairs(category.items or {}) do
                    if type(name) == 'string' then allowed[name:lower()] = true end
                end
            end
            break
        end
    end
    return allowed
end

---@param business table
---@param raw any
---@return table[]|nil items, integer|nil total, string|nil err
local function cleanSale(business, raw)
    if type(raw) ~= 'table' or #raw == 0 or #raw > 100 then return nil, nil, 'Add items to the sale first.' end
    local allowed, combined, total = salesCatalog(business), {}, 0
    for _, entry in ipairs(raw) do
        if type(entry) ~= 'table' or type(entry.item) ~= 'string' then return nil, nil, 'A sale item is invalid.' end
        local name = entry.item:lower()
        local amount, unitPrice = tonumber(entry.amount), tonumber(entry.unitPrice)
        if not allowed[name] then return nil, nil, ('%s is not on this business’s Sales Items list.'):format(name) end
        if not amount or amount ~= amount or amount % 1 ~= 0 or amount < 1 or amount > 100000 then
            return nil, nil, ('The quantity for %s is invalid.'):format(name)
        end
        if not unitPrice or unitPrice ~= unitPrice or unitPrice % 1 ~= 0 or unitPrice < 1 or unitPrice > Config.payment.maxAmount then
            return nil, nil, ('The price for %s is invalid.'):format(name)
        end
        if combined[name] and combined[name].unitPrice ~= unitPrice then
            return nil, nil, ('%s has conflicting prices in this sale.'):format(name)
        end
        local line = combined[name] or { item = name, amount = 0, unitPrice = unitPrice }
        line.amount = line.amount + amount
        combined[name] = line
    end

    local items = {}
    for _, line in pairs(combined) do
        local lineTotal = line.amount * line.unitPrice
        if lineTotal > Config.payment.maxAmount then return nil, nil, 'This sale exceeds the payment limit.' end
        total = total + lineTotal
        if total > Config.payment.maxAmount then return nil, nil, 'This sale exceeds the payment limit.' end
        items[#items + 1] = line
    end
    table.sort(items, function(a, b) return a.item < b.item end)
    return items, total
end

---Builds exact slot removals so transaction rollback preserves item metadata.
---@param src integer
---@param items table[]
---@return table[]|nil removals, string|nil err
local function inventoryRemovals(src, items)
    local data = exports.kora_core:getPlayerData(src)
    if type(data) ~= 'table' or type(data.items) ~= 'table' then return nil, 'Your inventory is unavailable.' end
    local slots = {}
    for slot, item in pairs(data.items) do
        if type(item) == 'table' and type(item.name) == 'string' then
            slots[#slots + 1] = { slot = tonumber(slot) or slot, item = item }
        end
    end
    table.sort(slots, function(a, b) return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0) end)

    local removals = {}
    for _, requested in ipairs(items) do
        local remaining = requested.amount
        for _, entry in ipairs(slots) do
            if remaining <= 0 then break end
            if entry.item.name == requested.item then
                local take = math.min(remaining, math.floor(tonumber(entry.item.amount) or 0))
                if take > 0 then
                    removals[#removals + 1] = {
                        item = requested.item, amount = take, slot = entry.slot, info = entry.item.info,
                    }
                    remaining = remaining - take
                end
            end
        end
        if remaining > 0 then return nil, ('You no longer have %dx %s.'):format(requested.amount, requested.item) end
    end
    return removals
end

local function transaction(src, definition)
    local called, ok, err = pcall(function() return exports.kora_core:transaction(src, definition) end)
    if not called then return false, tostring(ok) end
    return ok, err
end

local function refundBuyer(src, account, amount)
    return transaction(src, {
        reason = 'kora_jobcreator-sale-refund',
        money = { add = { { account = account, amount = amount } } },
    })
end

local function restoreSellerItems(src, removals)
    return transaction(src, {
        reason = 'kora_jobcreator-sale-item-rollback',
        items = { add = removals },
    })
end

---@param src integer
---@param target any
---@param businessId? string
---@param moduleId? string Till module id; nil means portable card machine.
---@param rawItems any
---@return boolean ok, string|nil err
function Payment.request(src, target, businessId, moduleId, rawItems)
    if inFlight[src] then return false, 'You already have a sale in progress.' end

    local business = businessFor(src, businessId)
    if not business then return false, 'You are not working for this business.' end
    local module = paymentModule(business, moduleId)
    if moduleId then
        if not module then return false, 'That till is no longer available.' end
        local nearTill = State.employeeAt(src, business, module)
        if not nearTill then return false, 'You must be at the till to take this payment.' end
    elseif not hasCardMachine(src) then
        return false, 'You need a card machine to take a portable payment.'
    end

    target = math.floor(tonumber(target) or 0)
    if target <= 0 then return false, 'Enter a valid customer server ID.' end
    if not exports.kora_core:getPlayerData(target) then return false, 'That player is not around.' end
    if target ~= src and Kora.world.resolveNearbyPlayer(src, target, { maxDistance = Config.payment.distance }) == nil then
        return false, 'They are too far away.'
    end
    if pendingCustomers[target] or (target ~= src and inFlight[target]) then return false, 'That player is already reviewing a payment.' end

    local items, total, cartErr = cleanSale(business, rawItems)
    if not items then return false, cartErr end
    local _, inventoryErr = inventoryRemovals(src, items)
    if inventoryErr then return false, inventoryErr end

    inFlight[src], pendingCustomers[target] = true, true
    local results = table.pack(pcall(function()
        local shared = {}
        local ok, value = pcall(function() return exports.kora_core:getShared('items') end)
        if ok and type(value) == 'table' then shared = value end
        local invoiceItems = {}
        for _, line in ipairs(items) do
            local definition = shared[line.item]
            invoiceItems[#invoiceItems + 1] = {
                item = line.item,
                label = type(definition) == 'table' and definition.label or line.item,
                amount = line.amount,
                unitPrice = line.unitPrice,
                image = type(definition) == 'table' and definition.image or nil,
            }
        end

        local account = Kora.callback.trigger(target, 'kora_jobcreator:client:approveSale', {
            business = business.label, items = invoiceItems, total = total,
        })
        if account ~= 'cash' and account ~= 'bank' then return false, 'The customer declined the payment.' end
        if not exports.kora_core:getPlayerData(target) then return false, 'The customer left.' end
        if target ~= src and Kora.world.resolveNearbyPlayer(src, target, { maxDistance = Config.payment.distance }) == nil then
            return false, 'They walked away.'
        end

        local currentBusiness = businessFor(src, business.id)
        if not currentBusiness then return false, 'You no longer work for this business.' end
        if moduleId then
            local currentModule = paymentModule(currentBusiness, moduleId)
            if not currentModule or not State.employeeAt(src, currentBusiness, currentModule) then
                return false, 'You must remain at the till to take this payment.'
            end
            module = currentModule
        elseif not hasCardMachine(src) then
            return false, 'You no longer have a card machine.'
        end
        local currentItems, currentTotal, currentCartErr = cleanSale(currentBusiness, items)
        if not currentItems or currentTotal ~= total then return false, currentCartErr or 'The Sales Items list changed.' end
        business, items = currentBusiness, currentItems

        local removals, freshInventoryErr = inventoryRemovals(src, items)
        if not removals then return false, freshInventoryErr end
        local removed, removeErr = transaction(src, {
            reason = 'kora_jobcreator-sale-items',
            items = { remove = removals },
        })
        if not removed then return false, removeErr or 'Could not remove the sale items.' end

        local charged, chargeErr = transaction(target, {
            reason = 'kora_jobcreator-sale-payment',
            money = { remove = { { account = account, amount = total } } },
        })
        if not charged then
            local restored, restoreErr = restoreSellerItems(src, removals)
            if not restored then
                Kora.logging.error('payment.sale_item_restore_failed', 'Could not restore sale items after payment rejection', {
                    seller = src, error = tostring(restoreErr),
                })
            end
            return false, chargeErr or 'The customer does not have enough money.'
        end

        local commission = math.max(math.min(math.floor(total * Config.payment.commission), total), 0)
        local toBusiness = total - commission
        local creditCallOk, credited, creditErr = pcall(Pos.credit, business.job, toBusiness, 'item sale')
        if not creditCallOk then creditErr, credited = tostring(credited), false end
        if not credited then
            local refunded, refundErr = refundBuyer(target, account, total)
            local restored, restoreErr = restoreSellerItems(src, removals)
            if not refunded or not restored then
                Kora.logging.error('payment.sale_rollback_failed', 'Could not fully roll back a failed item sale', {
                    seller = src, customer = target, refunded = refunded, refundError = tostring(refundErr),
                    itemsRestored = restored, itemError = tostring(restoreErr),
                })
            end
            return false, creditErr or 'The business account is unavailable.'
        end

        if commission > 0 then
            local commissionAmount = commission
            local callOk, paid, commissionErr = pcall(function()
                return exports.kora_core:addMoney(src, 'bank', commissionAmount, 'kora_jobcreator-sale-commission')
            end)
            if not callOk then commissionErr, paid = tostring(paid), false end
            if not paid then
                local creditCommissionCallOk, creditedCommission, commissionCreditErr = pcall(
                    Pos.credit, business.job, commissionAmount, 'unpaid sale commission'
                )
                if not creditCommissionCallOk then commissionCreditErr, creditedCommission = tostring(creditedCommission), false end
                if not creditedCommission then
                    Kora.logging.error('payment.sale_commission_failed', 'Could not pay the seller or return the commission to the business', {
                        seller = src, business = business.id, error = tostring(commissionErr),
                        creditError = tostring(commissionCreditErr),
                    })
                end
                commission = 0
                toBusiness = toBusiness + (creditedCommission and commissionAmount or 0)
            end
        end

        local method = account == 'cash' and 'cash' or 'card'
        pcall(function()
            Kora.notify.send(target, {
                title = Config.notifyTitle, message = ('Paid %s $%d by %s.'):format(business.label, total, method), type = 'success',
            })
        end)
        if src ~= target then
            pcall(function()
                Kora.notify.send(src, { title = Config.notifyTitle, message = ('Sold items for $%d.'):format(total), type = 'success' })
            end)
        end

        local summary, loggedSummary = {}, {}
        for _, line in ipairs(items) do summary[#summary + 1] = ('%dx %s'):format(line.amount, line.item) end
        for index = 1, math.min(#summary, 10) do loggedSummary[index] = summary[index] end
        if #summary > #loggedSummary then loggedSummary[#loggedSummary + 1] = ('… and %d more item types'):format(#summary - #loggedSummary) end
        pcall(function()
            Logs.record(business, {
                category = 'payment', src = src, amount = toBusiness,
                message = ('Sold %s for $%d by %s.'):format(table.concat(loggedSummary, ', '), total, method),
                fields = {
                    { name = 'Items', value = table.concat(loggedSummary, '\n'), inline = false },
                    { name = 'Payment method', value = method, inline = true },
                    { name = 'Commission', value = ('$%d'):format(commission), inline = true },
                    { name = 'To business', value = ('$%d'):format(toBusiness), inline = true },
                },
            })
        end)
        return true
    end))

    inFlight[src], pendingCustomers[target] = nil, nil
    if not results[1] then
        Kora.logging.error('payment.sale_failed', 'Item sale failed unexpectedly', { error = tostring(results[2]) })
        return false, 'The sale could not be completed.'
    end
    return table.unpack(results, 2, results.n)
end

Kora.callback.register('kora_jobcreator:server:requestPayment', function(src, target, businessId, moduleId, items)
    return Payment.request(src, target, businessId, moduleId, items)
end, { rateLimit = { max = 5, window = 15000 } })
