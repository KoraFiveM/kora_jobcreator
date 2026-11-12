-- Boot sequence and lifecycle.

KoraJobCreator = KoraJobCreator or {}

local State = KoraJobCreator.state
local Pos = KoraJobCreator.pos
local Logs = KoraJobCreator.logs

CreateThread(function()
    if not Kora.sql.ready(60000) then
        return print('^1[kora_jobcreator]^7 kora_sql was not ready; resource disabled.')
    end

    local reports, err = Kora.sql.ensureTables(KoraJobCreatorTables)
    if err then return print(('^1[kora_jobcreator]^7 schema failed: %s'):format(err)) end

    for _, report in ipairs(reports or {}) do
        for _, warning in ipairs(report.warnings or {}) do
            print(('^3[kora_jobcreator]^7 schema %s: %s'):format(report.table, warning))
        end
    end

    Pos.loadPrices()

    local ok, loadErr = State.load()
    if not ok then return print(('^1[kora_jobcreator]^7 could not load businesses: %s'):format(tostring(loadErr))) end

    State.ready = true

    local count = 0
    for _ in pairs(State.businesses) do count = count + 1 end
    print(('^2[kora_jobcreator]^7 %d business(es) live.'):format(count))

    State.broadcast()
end)

---A client that just loaded a character asks for the world it should build.
---This is deliberately a push rather than relying on the join-time broadcast:
---a player who connects mid-restart would otherwise see nothing.
RegisterNetEvent('QBCore:Server:PlayerLoaded', function()
    if State.ready then State.broadcast(source) end
end)

---Log trimming is periodic rather than per-write: a busy till writes several
---rows a minute, and a DELETE after each one would cost more than it saves.
CreateThread(function()
    while true do
        Wait(15 * 60 * 1000)
        if State.ready then
            for id in pairs(State.businesses) do Logs.trim(id) end
        end
    end
end)
