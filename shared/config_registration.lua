-- Static recipe, shop-list, and business seed files load before this bridge so
-- their authored values can be edited alongside the base policy settings.
Config.recipes = Kora.config.map(Config.recipes, Kora.config.object({}), {
    label = 'Crafting recipe library',
    description = 'Maps each reusable recipe ID to its trusted crafting definition, including ingredients, output, timing, and optional skill requirements. Business modules refer to these stable IDs; malformed recipes are rejected by the shared business schema after the resource restarts.',
})
Config.shopItems = Kora.config.map(Config.shopItems, Kora.config.list({}, Kora.config.object({})), {
    label = 'Shop item libraries',
    description = 'Maps each reusable shop-list name to an ordered array of fixed-price item definitions. Point-of-sale modules reference the list name, so edits affect every business seed or live definition that uses that library after the resource restarts.',
})
Config.seeds = Kora.config.list(Config.seeds, Kora.config.object({}), {
    label = 'First-boot business seeds',
    description = 'Defines the ordered first-boot business definitions. Each row contains its own stable business ID; seeds are inserted only when the database has no business or deletion marker with that ID and never overwrite in-game edits, so changing an existing seed does not replace an already-created business.',
})
Config = Kora.config.adopt(Config)
