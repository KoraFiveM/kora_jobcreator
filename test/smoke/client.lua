-- Client-realm invariants that are easy to regress and impossible to see.
--
-- The hard one is threading. kora_lib's zone tick and kora_target's target loop are
-- SHARED across every resource that uses them, and both invoke callbacks this
-- resource supplies. Yielding inside one of those callbacks -- which almost
-- everything here does, since streaming a prop, opening a dialog and calling
-- the server all yield -- stalls every zone or every target in the server, not
-- just ours.

local H = dofile('test/harness.lua')

local function read(path)
    local file = assert(io.open(path, 'r'), 'missing ' .. path)
    local source = file:read('*a')
    file:close()
    return source
end

local business = read('client/business.lua')
local main = read('client/main.lua')
local creator = read('client/creator.lua')
local payment = read('client/payment.lua')
local state = read('client/state.lua')

local enter = business:match('function Business%.enter%(business%).-\nend')
H.ok(enter, 'Business.enter exists')
H.ok(enter:find('business.inside = true', 1, true), 'the re-entry guard is set synchronously')
H.ok(enter:find('CreateThread(function()', 1, true), 'the yielding work runs on its own thread')
H.ok(enter:find('business.generation ~= generation', 1, true),
    'a build finishing after the player left cleans up instead of orphaning props')

local attach = business:match('function Business%.attach%(business.-\nend\n')
H.ok(attach and attach:find('option.onSelect = runSelection', 1, true),
    'every target option is wrapped before registration')
H.ok(attach and attach:find('option.action = runSelection', 1, true),
    'kora_lib interactions receive the same wrapped selection action')
H.ok(attach and attach:find('CreateThread(function() select_', 1, true),
    'onSelect never yields on qbtarget\'s own tick thread')

H.ok(main:find("RegisterNetEvent('QBCore:Client:OnJobUpdate'", 1, true), 'job changes are handled')
local jobUpdate = main:match("RegisterNetEvent%('QBCore:Client:OnJobUpdate'.-\nend%)")
H.ok(jobUpdate and jobUpdate:find('CreateThread', 1, true),
    'the job-update handler does not call the server on the event thread')

--
-- `cache` and `lib` are ox_lib globals. kora_lib has neither, and referencing one
-- is a nil index at the worst possible moment rather than a load error.
for name, source in pairs({ business = business, main = main, creator = creator,
    payment = payment, state = state }) do
    local stripped = source:gsub('%-%-[^\n]*', '')
    H.nope(stripped:find('cache%.[%w_]+'), ('%s does not use the ox_lib cache global'):format(name))
    H.nope(stripped:find('[^%w_]lib%.[%w_]+'), ('%s does not use the ox_lib global'):format(name))
end

H.ok(business:find('local function clearScope', 1, true), 'there is one teardown path')
local clear = business:match('local function clearScope.-\nend')
for _, kind in ipairs({ 'zones', 'blips', 'targets', 'entities' }) do
    H.ok(clear:find('scope.' .. kind, 1, true), ('clearScope releases %s'):format(kind))
end
H.ok(clear:find('pcall(zone.remove)', 1, true),
    'a zone handle exposes a plain remove function, not a method')
H.ok(business:find('Kora.interact.addEntity', 1, true)
    and business:find('Kora.interact.addCircleZone', 1, true)
    and business:find('Kora.interact.addBoxZone', 1, true),
    'entity, sphere and box interactions use kora_lib')
H.ok(business:find("module.zoneType == 'poly'", 1, true)
    and business:find('target:addPolyZone', 1, true),
    'qbtarget is retained only for polygon interactions unsupported by Kora.interact')
-- Entities must go last: a target registration still points at them.
H.ok(clear:find('scope.targets', 1, true) < clear:find('for _, entity in ipairs(scope.entities)', 1, true),
    'targets are removed before the entities they point at')

H.nope(creator:find('SaveResourceFile', 1, true), 'the builder never writes a file')
H.nope(creator:find('setClipboard', 1, true), 'the builder never hands back a snippet to paste')
H.ok(creator:find("Kora.callback.trigger('qbjobcreator:server:saveModule'", 1, true),
    'a built module goes straight to the server')
H.ok(creator:find('Kora.zones.startCreator', 1, true), 'zones are placed in-world')
H.ok(creator:find('Kora.placement.start', 1, true), 'props are placed in-world')
H.ok(creator:find('Kora.raycast.fromCamera', 1, true), 'an existing object is picked by looking at it')

H.ok(creator:find("local APP_ID = 'qbjobcreator:management'", 1, true),
    'the management console has one namespaced AppShell id')
H.ok(creator:find('Kora.nui.registerApp(definition)', 1, true),
    'business management is registered with AppShell')
H.ok(creator:find("openManagement(state, 'management', 'modules')", 1, true),
    'the console resumes on the selected business module tab after an editor')
H.ok(creator:find("id = 'businesses:add-module'", 1, true)
    and creator:find("id = 'businesses:edit-module'", 1, true),
    'module creation and rebuilding are AppShell actions')
H.ok(creator:find('closeBeforeAction = true', 1, true),
    'world-editor actions release AppShell focus before running')
H.ok(creator:find('state.moduleIndex = position or index', 1, true),
    'editor resume preserves the selected module')
H.ok(creator:find('function Creator.refresh()', 1, true)
    and main:find('Creator.refresh()', 1, true),
    'replicated business and staff changes refresh an open management console')
H.ok(creator:find("Kora.callback.trigger('qbjobcreator:server:removeModule'", 1, true)
    and creator:find("Kora.callback.trigger('qbjobcreator:server:editBusiness'", 1, true)
    and creator:find("Kora.callback.trigger('qbjobcreator:server:deleteBusiness'", 1, true),
    'AppShell actions still submit intent through the authoritative server callbacks')

local crafting = creator:match('fieldsFor%.Crafting = function%(%).-\nend')
H.ok(crafting and crafting:find("type = 'multiselect'", 1, true),
    'crafting benches choose recipes with the shared multiselect field')
H.ok(crafting and crafting:find('recipes = values.recipes', 1, true),
    'the selected recipe ids are forwarded as intent for schema validation')
H.nope(crafting and crafting:find('while true do', 1, true),
    'crafting no longer loops through one recipe picker per selection')

-- Execute the real sync lifecycle with plain business records, as create returns.
local handlers, created, destroyed, stopping = {}, {}, {}, {}
local refreshes, leaveAll = 0, 0
local clientState = { definitions = {} }
QbJobCreator = {
    client = clientState,
    Business = {
        create = function(definition)
            local record = { definition = definition }
            created[#created + 1] = record
            return record
        end,
        destroy = function(record, isStopping)
            destroyed[#destroyed + 1] = record
            stopping[#destroyed] = isStopping
        end,
    },
    creator = { refresh = function() refreshes = refreshes + 1 end },
}
GetCurrentResourceName = function() return 'kora_jobcreator' end
RegisterNetEvent = function(name, callback) handlers[name] = callback end
AddEventHandler = RegisterNetEvent
CreateThread, exports = function() end, function() end
TriggerServerEvent = function(name)
    H.equal(name, 'qbjobcreator:server:leaveAll', 'resource stop retains its presence cleanup event')
    leaveAll = leaveAll + 1
end
dofile(arg[1] or 'client/main.lua')
local sync = handlers['qbjobcreator:client:sync']
local first, neighbour = { id = 'one', rev = '1' }, { id = 'two', rev = '1' }
sync({ first, neighbour })
local original
for _, record in ipairs(created) do if record.definition == first then original = record end end
H.equal(#created, 2, 'initial sync creates both businesses')
H.equal(#destroyed, 0, 'initial sync has nothing to tear down')
sync({ { id = 'one', rev = '1' }, neighbour })
H.equal(#created, 2, 'unchanged revision keeps live business handles')
H.equal(clientState.definitions.one, first, 'unchanged revision retains its definition')
local replacement = { id = 'one', rev = '2' }
sync({ replacement, neighbour })
H.equal(#destroyed, 1, 'changed revision tears down only the old business')
H.equal(destroyed[1], original, 'cleanup receives the existing plain business record')
H.equal(stopping[1], nil, 'normal replacement retains ordinary cleanup behavior')
H.equal(#created, 3, 'changed revision creates one replacement')
H.equal(created[3].definition, replacement, 'replacement uses the new definition')
H.equal(clientState.definitions.one, replacement, 'changed definition reaches the client mirror')
H.equal(clientState.definitions.two, neighbour, 'unchanged neighbour is preserved')
H.equal(refreshes, 3, 'changed sync completes the creator refresh')
sync({ neighbour })
H.equal(destroyed[2], created[3], 'removed business uses the same cleanup function')
H.equal(clientState.definitions.one, nil, 'removed definition is cleared')
clientState.setDebug(true)
H.equal(clientState.debug, true, 'debug preference still updates')
H.equal(#destroyed, 3, 'debug rebuild keeps its cleanup path')
H.equal(#created, 4, 'debug rebuild creates one remaining business')
handlers.onClientResourceStop('other')
H.equal(#destroyed, 3, 'another resource stopping does not affect businesses')
handlers.onClientResourceStop('kora_jobcreator')
H.equal(destroyed[4], created[4], 'stop cleans up the current replacement record')
H.equal(stopping[4], true, 'stop retains the flag that skips extra server round trips')
H.equal(leaveAll, 1, 'stop publishes presence cleanup once')

H.finish('client')
