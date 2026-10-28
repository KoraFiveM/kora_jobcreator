-- Actual logging and Discord adapter; SQL, event and HTTP boundaries are inert.
local H = dofile('test/harness.lua')
local eq = H.equal
local logsPath = arg[1] or 'server/logs.lua'
local function read(path)
    local file = assert(io.open(path, 'rb')); local source = file:read('*a'); file:close(); return source
end
local source = read(logsPath)

local sqlRecords, logRecords, queued, httpRecords, embeds = {}, {}, {}, {}, {}
local convarReads = 0
QB = { util = {}, discord = {}, compat = { isCallable = function(value) return type(value) == 'function' end } }
dofile('../kora_lib/modules/util/shared.lua')
local clone = QB.util.deepClone
local snapshots, nextToken = {}, 0
json = {
    encode = function(value) nextToken = nextToken + 1; local token = 'snapshot:' .. nextToken; snapshots[token] = clone(value); return token end,
    decode = function(token) return clone(assert(snapshots[token], 'unknown inert snapshot token')) end,
}
RegisterCommand, AddEventHandler, CreateThread = function() end, function() end, function() end
GetConvar = function() convarReads = convarReads + 1; return '' end
SetTimeout = function() error('fixture HTTP204 cannot require a retry') end
local M, J, D = 'https://module.invalid/webhook', 'https://job.invalid/webhook', 'https://default.invalid/webhook'
local fakeURLs = { [M] = true, [J] = true, [D] = true }
PerformHttpRequest = function(url, callback, method, body, headers)
    eq(fakeURLs[url], true, 'inert HTTP boundary only receives synthetic fixture URLs')
    httpRecords[#httpRecords + 1] = { url = url, method = method, body = json.decode(body), headers = clone(headers) }
    callback(204, '', {}, '')
end
dofile('../kora_lib/modules/discord/server.lua')
local createEmbed, sendWebhook = QB.discord.createEmbed, QB.discord.sendWebhook
QB.discord.createEmbed = function(options)
    local embed = createEmbed(options); embeds[#embeds + 1] = clone(embed); return embed
end
QB.discord.sendWebhook = function(url, payload, callback)
    local result = sendWebhook(url, payload, callback)
    queued[#queued + 1] = { url = url, payload = clone(payload), result = result, callback = callback }
    return result
end
QB.sql = { insertAsync = function(sql, params, callback)
    eq(sql:find('INSERT INTO `qbjobcreator_logs`', 1, true) ~= nil, true, 'existing append-only log table remains')
    sqlRecords[#sqlRecords + 1] = { sql = sql, params = clone(params) }
    callback(1)
end }
QB.logging = { event = function(name, src, values)
    logRecords[#logRecords + 1] = { name = name, src = src, values = clone(values) }
end }
exports = { kora_core = { getPlayerData = function(_, src)
    if src == 1 then return { citizenid = 'SYNTH001', name = 'unknown', charinfo = { firstname = 'Fixture', lastname = 'Person' } } end
end } }
Config = { webhooks = {}, logs = { retain = 50 } }
assert(load(source, '@' .. logsPath))()
local Logs = QbJobCreator.logs
local business = { id = 'synthetic-business', job = 'fixture', label = 'Synthetic Business' }
local function expectURLs(actual, expected, label)
    eq(#actual, #expected, label .. ' count')
    for index, url in ipairs(expected) do eq(actual[index].url, url, label .. ' order ' .. index) end
end
local function run(label, moduleURL, jobURL, defaultURL, expected, entry)
    sqlRecords, logRecords, queued, httpRecords, embeds = {}, {}, {}, {}, {}
    Config.webhooks = { fixture = jobURL, default = defaultURL }
    entry = clone(entry or { category = 'craft', message = 'Synthetic fixture event.' })
    entry.webhook = moduleURL
    local result = Logs.record(business, entry)
    expectURLs(queued, expected, label .. ' selected webhook')
    local expectedHTTP = {}
    for _, url in ipairs(expected) do if url ~= ' ' then expectedHTTP[#expectedHTTP + 1] = url end end
    expectURLs(httpRecords, expectedHTTP, label .. ' inert HTTP')
    eq(#embeds, #expected > 0 and 1 or 0, label .. ' builds one shared embed only when needed')
    eq(result, nil, label .. ' preserves nil Logs.record return')
    eq(#sqlRecords, 1, label .. ' retains durable log independently of webhook presence')
    eq(#logRecords, 1, label .. ' retains qblib event independently of webhook presence')
    eq(sqlRecords[1].params[1], business.id, label .. ' durable log business unchanged')
    eq(sqlRecords[1].params[2], entry.category, label .. ' durable log category unchanged')
    eq(sqlRecords[1].params[3], tostring(entry.message):sub(1, 512), label .. ' durable message truncation unchanged')
    eq(logRecords[1].name, 'qbjobcreator:' .. entry.category, label .. ' qblib event name unchanged')
    eq(logRecords[1].values.message, sqlRecords[1].params[3], label .. ' both log sinks share the same bounded message')
    for _, delivery in ipairs(queued) do
        eq(delivery.callback, nil, label .. ' keeps existing optional callback contract')
        eq(delivery.result, delivery.url ~= ' ', label .. ' actual Discord adapter queued result')
        eq(delivery.payload.username, 'Businesses', label .. ' webhook username unchanged')
        eq(#delivery.payload.embeds, 1, label .. ' existing payload remains single-embed')
        eq(delivery.payload.embeds[1].title, business.label .. ': ' .. entry.category, label .. ' embed title unchanged')
        eq(delivery.payload.embeds[1].description, sqlRecords[1].params[3], label .. ' embed message unchanged')
    end
    for _, request in ipairs(httpRecords) do
        eq(request.method, 'POST', label .. ' actual adapter retains POST')
        eq(request.headers['Content-Type'], 'application/json', label .. ' actual adapter retains JSON header')
        eq(request.body.username, 'Businesses', label .. ' inert wire body preserves payload')
    end
end
run('default only with nil first and second slots', nil, nil, D, { D })
run('job only with nil first slot', nil, J, nil, { J })
run('job and default with nil first slot', nil, J, D, { J, D })
run('module and default with nil second slot', M, nil, D, { M, D })
run('module only', M, nil, nil, { M })
run('all three distinct URLs', M, J, D, { M, J, D })
run('all three URLs identical', M, M, M, { M })
run('duplicate job/default after first hole', nil, J, J, { J })
run('duplicate module/default across middle hole', M, nil, M, { M })
run('empty module and missing job', '', nil, D, { D })
run('false module and empty job preserve type/empty guards', false, '', D, { D })
run('invalid first two values preserve type guard', 42, {}, D, { D })
run('missing module and invalid job', nil, false, D, { D })
run('all URLs missing', nil, nil, nil, {})
run('all URLs empty', '', '', '', {})
run('all URL types invalid', false, 42, {}, {})
run('empty default with two explicit recipients', M, J, '', { M, J })
run('duplicate job/default after module', M, J, J, { M, J })
run('whitespace candidate retains existing provider behavior', nil, nil, ' ', { ' ' })
for _, category in ipairs({ 'sale', 'stock', 'payment', 'craft', 'admin', 'panic' }) do
    run('default applies to ' .. category, nil, nil, D, { D }, { category = category, message = 'Synthetic ' .. category .. ' fixture.' })
end
run('actor amount fields and bounded message', M, J, D, { M, J, D }, {
    category = 'payment', src = 1, amount = 123.8, message = string.rep('x', 520),
    fields = { { name = 'Synthetic extra field', value = 'Fixture value', inline = false } },
})
eq(sqlRecords[1].params[4], 'SYNTH001', 'SQL actor citizenid preserved')
eq(sqlRecords[1].params[5], 123, 'SQL amount floor preserved')
eq(logRecords[1].src, 1, 'qblib event actor source preserved')
eq(logRecords[1].values.amount, 123.8, 'qblib event amount contract preserved')
eq(embeds[1].color, 0x9b59b6, 'actual payment embed color preserved')
eq(#embeds[1].fields, 3, 'existing business/player/extra field ordering preserved')
eq(embeds[1].fields[1].name, 'Business', 'business field remains first')
eq(embeds[1].fields[2].value, 'Fixture Person (1)', 'existing actor name fallback preserved')
eq(embeds[1].fields[3].inline, false, 'actual createEmbed preserves explicit false field option')
eq(convarReads, 0, 'missing QB resource candidates do not introduce qblib convar fallback')
H.finish('webhook_fallback')
