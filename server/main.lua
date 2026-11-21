-- Boot sequence and lifecycle.

KoraJobCreator = KoraJobCreator or {}

local State = KoraJobCreator.state
local Pos = KoraJobCreator.pos
local Logs = KoraJobCreator.logs

CreateThread(function()
    if not Kora.sql.ready(60000) then
        Kora.logging.error('sql.not_ready', 'kora_sql was not ready; resource disabled')
        return
    end

    local reports, err = Kora.sql.ensureTables(KoraJobCreatorTables)
    if err then Kora.logging.error('schema.setup_failed', 'Schema setup failed', { error = tostring(err) }) return end

    for _, report in ipairs(reports or {}) do
        for _, warning in ipairs(report.warnings or {}) do
            Kora.logging.warn('schema.warning', 'Schema check reported a warning', { table = tostring(report.table), warning = tostring(warning) })
        end
    end

    Pos.loadPrices()

    -- Recipes load before businesses so a crafter is never live without the
    -- recipes its categories reference.
    local recipesOk, recipesErr = KoraJobCreator.recipes.load()
    if not recipesOk then Kora.logging.error('recipes.load_failed', 'Could not load business recipes', { error = tostring(recipesErr) }) end

    local ok, loadErr = State.load()
    if not ok then Kora.logging.error('businesses.load_failed', 'Could not load businesses', { error = tostring(loadErr) }) return end

    State.ready = true

    local count = 0
    for _ in pairs(State.businesses) do count = count + 1 end
    Kora.logging.info('businesses.live', 'Businesses are live', { count = count })

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
