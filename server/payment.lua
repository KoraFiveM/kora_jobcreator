-- The portable card machine: an employee bills a nearby player, the business
-- takes the money, the employee takes a commission.
--
-- Both halves of the transaction are confirmed by their own owner -- the
-- employee names the amount, the customer approves it -- and the server
-- re-checks the distance between them after both answers, not just before,
-- because a player can walk away mid-dialog.

QbJobCreator = QbJobCreator or {}

local State = QbJobCreator.state
local Logs = QbJobCreator.logs
local Pos = QbJobCreator.pos

local Payment = {}
QbJobCreator.payment = Payment

---@type table<integer, true> employees with a bill already in flight
local inFlight = {}

AddEventHandler('playerDropped', function() inFlight[source] = nil end)

---The business an employee is billing on behalf of: the one matching their
---current job. A player with no business for their job cannot take payments.
---@param src integer
---@return table|nil
local function businessFor(src)
    local job = State.playerJob(src)
    if not job or not job.name then return nil end
    for _, business in pairs(State.businesses) do
        if business.job == job.name then return business end
    end
    return nil
end

---@param src integer
---@param target integer
---@return boolean
local function nearEachOther(src, target)
    return Kora.world.resolveNearbyPlayer(src, target, { maxDistance = Config.payment.distance }) ~= nil
end

---@param src integer
---@param target any Server id of the customer.
---@return boolean ok, string|nil err
function Payment.request(src, target)
    if inFlight[src] then return false, 'You already have a payment in progress.' end

    local business = businessFor(src)
    if not business then return false, 'You are not working for a business.' end

    target = math.floor(tonumber(target) or 0)
    if target <= 0 or target == src then return false, 'Pick someone else.' end
    if not exports.kora_core:getPlayerData(target) then return false, 'That player is not around.' end
    if not nearEachOther(src, target) then return false, 'They are too far away.' end

    inFlight[src] = true
    -- table.pack/unpack rather than a bare `local ok, err = pcall(...)`: the
    -- body returns (false, reason) on every rejection, and a two-value capture
    -- would silently drop every one of those reasons.
    local results = table.pack(pcall(function()
        local answer = Kora.callback.trigger(src, 'qbjobcreator:client:billAmount', { max = Config.payment.maxAmount })
        local amount = math.floor(tonumber(answer) or 0)
        if amount <= 0 or amount > Config.payment.maxAmount then return false, 'That amount is not valid.' end

        local approved = Kora.callback.trigger(target, 'qbjobcreator:client:approveBill', {
            amount = amount, business = business.label,
        })
        -- A timed-out callback returns nothing, which is not the same thing as
        -- a refusal -- but the outcome here is identical: no consent, no charge.
        if approved ~= true then return false, 'The payment was declined.' end

        if not nearEachOther(src, target) then return false, 'They walked away.' end

        local paid, payErr = exports.kora_core:removeMoney(target, Config.payment.account, amount, 'qbjobcreator-card-payment')
        if not paid then return false, payErr or 'Their payment was declined.' end

        local commission = math.floor(amount * Config.payment.commission)
        local toBusiness = amount - commission

        if commission > 0 then
            exports.kora_core:addMoney(src, 'bank', commission, 'qbjobcreator-payment-commission')
        end

        local credited, creditErr = Pos.credit(business.job, toBusiness, 'card payment')
        if not credited then
            -- The business account is unreachable, and the employee is not
            -- allowed to keep the difference, so the customer is made whole.
            exports.kora_core:addMoney(target, Config.payment.account, amount, 'qbjobcreator-card-refund')
            if commission > 0 then exports.kora_core:removeMoney(src, 'bank', commission, 'qbjobcreator-payment-rollback') end
            return false, creditErr or 'The business account is unavailable.'
        end

        Kora.notify.send(target, {
            title = Config.notifyTitle, message = ('You paid %s $%d.'):format(business.label, amount), type = 'success',
        })
        Kora.notify.send(src, {
            title = Config.notifyTitle,
            message = commission > 0 and ('Took $%d. Your commission: $%d.'):format(amount, commission) or ('Took $%d.'):format(amount),
            type = 'success',
        })

        Logs.record(business, {
            category = 'payment', src = src, amount = toBusiness,
            message = ('Billed a customer $%d.'):format(amount),
            fields = {
                { name = 'Commission', value = ('$%d'):format(commission), inline = true },
                { name = 'To business', value = ('$%d'):format(toBusiness), inline = true },
            },
        })
        return true
    end))

    inFlight[src] = nil
    if not results[1] then
        print(('^1[qbjobcreator]^7 card payment failed: %s'):format(tostring(results[2])))
        return false, 'The payment could not be completed.'
    end
    return table.unpack(results, 2, results.n)
end

Kora.callback.register('qbjobcreator:server:requestPayment', function(src, target)
    return Payment.request(src, target)
end, { rateLimit = { max = 5, window = 15000 } })
