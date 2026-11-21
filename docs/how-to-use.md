---
title: "How to use"
sidebar_position: 3
---


# How to use

Kora Job Creator separates WHAT a business is made of (modules, recipes, shop lists — this resource's schema) from WHERE it physically lives (placed in-game, never hand-authored coordinates). Read this page before adding a business; the burgershot seed is the shape every concept below refers to.

## Business and module concepts

- A **business** is `{ id, label, job, modules[] }`. `id` is a slug (lowercase, punctuation stripped) and the primary key; `job` is the kora_core job name staff and tills are gated by. Every mutation (`createBusiness`, `editBusiness`, `saveModule`, `removeModule`, `deleteBusiness`) re-validates and re-persists the WHOLE business as one row — there is no partial update path — so a rejected edit always leaves the database and the live server exactly as they were.
- A **module** is one placed thing: `Zone` (perimeter), `Blip`, `StaticEntity` (decorative prop/ped), `BossMenu`, `POS` (till or closed shop), `Stash`, `Crafting` (a single bench, or a crafter with categories), `UseableItem` (server-only, no world anchor) or `SalesItems` (the business-wide sales list and employee stores, one per business). Each module type declares what kind of world anchor it accepts via `interaction`: `zone` (trigger volume only), `model` (a spawned or adopted entity), `any` (builder's choice) or `none`.
- A module anchor is either a **zone** (`sphere`, `box` or `poly`, with `coords`/`radius`/`size`+`rotation`/`points`+`thickness`) or one or more **model** coordinates (`{ model, modelType, existing?, anim?, freeze? }` placed at up to 32 points — a till row of several identical registers is one module). `S.normaliseModule` in `shared/schema.lua` is the ONE validator for both realms: the server runs it before anything is written or broadcast, and the client re-runs it on receipt so a malformed module only skips itself instead of failing the whole business.
- **Startup vs. dynamic**: if a business has a `Zone` module, every other module is built lazily when a player enters that zone and torn down when they leave (a server with fifty businesses does not hold fifty tills' worth of props and target registrations at once). `Zone` and `Blip` modules are always "startup" (built immediately). A business with NO `Zone` module has nothing to trigger lazy building, so every one of its modules is treated as startup instead.
- `public` on a module skips the job lock for supported target options, such as a public stash. Crafting and employee stores always require the player's job to match the business. A closed shop's customer "Browse shop" option is hidden while on-duty staff are in the business.

## Adding a new business

1. **In-game (recommended)** — Run `/jobcreator` (`Config.command`). An administrator sees the full business directory with a "Create business" Appshell action (name + an existing kora_core job); anyone with a boss grade sees only the businesses they manage. Creating a business opens the module editor to place its first `Zone`. An admin's business workspace has these pages: Overview, Modules, Tills, Stashes, Sales Items, Stores, Recipes, Crafters, Activity and Debug (see [Commands](./commands.md#console)). For world placement the console closes before handing off to kora_lib's zone creator, prop placer or a camera raycast, then reopens on the same page. Coordinates are never typed in by hand.

   - **Sales Items** lists what staff may sell through itemized payments (and what a closed shop accepts). Items are picked from the shared item registry.
   - **Stores** are employee pickup lists: create a store, add items with a price, choose whether the employee or the business account pays, then **Place store** at one or more points. Staff pick a quantity from an Appshell catalog; supply is unlimited and no `kora_inventory` shop is involved.
   - **Recipes** are saved in SQL for that business only. Each has ingredients, outputs, a craft time and optional progress and completion text. Shared `Config.recipes` stay available everywhere.
   - **Crafters** group categories (Drinks, Prep, Grill...). Each category has its own recipe list and one or more placed locations, optionally tied to a prop model you must aim at. A single anchored bench made from Modules → Add module still works and appears here too.
   - **Tills** and **Stashes** place new ones and edit their settings (label, closed shop, tax, commission, currency, panic button; label, slots, weight, access) without touching their placement or contents.

2. **As a first-boot seed (for a server you are provisioning)** — Add a file under `shared/businesses/` (loaded by the `shared/businesses/*.lua` glob) that appends to `Config.seeds`. A seed is inserted only if no business AND no deletion marker with that id exists yet, so it never overwrites an admin's in-game edits or resurrects something they deleted. A seed may optionally carry `jobDefinition`, registered via `exports.kora_core:registerShared('jobs', ...)` ONLY if no job with that name is already registered — this runs every boot (kora_core's shared registries are rebuilt from scratch each start) but never overrides a server's own job of the same name.

   ```lua title="shared/businesses/burgershot.lua"
   -- shared/businesses/burgershot.lua — a worked FIRST-BOOT seed.
   -- Seeds are inserted only if no business or deletion marker with this id
   -- exists yet. An admin who edits or deletes it in-game is never overwritten
   -- on the next restart.
   Config.seeds[#Config.seeds + 1] = {
       id = 'burgershot', label = 'Burger Shot', job = 'burgershot',

       -- Registered at boot ONLY if no job by this name exists yet.
       jobDefinition = {
           label = 'Burger Shot', type = 'civ', defaultDuty = false, offDutyPay = false,
           grades = {
               { name = 'Trainee', payment = 30 },
               { name = 'Cook', payment = 45 },
               { name = 'Shift Lead', payment = 60 },
               { name = 'Manager', payment = 85, isboss = true },
           },
       },

       modules = {
           { moduleType = 'Zone', label = 'Burger Shot', controlDuty = true,
             zoneType = 'sphere', coords = { x = -1193.0, y = -893.0, z = 13.9 }, radius = 22.0 },
           { moduleType = 'Blip', label = 'Burger Shot', category = 'Restaurant',
             coords = { x = -1193.0, y = -893.0, z = 13.9 }, sprite = 106, color = 1 },
           { moduleType = 'POS', label = 'Front Till', id = 'burgershot_till', items = { 'burgershot' },
             commission = 5, tax = 10, hideWhenStaffed = true, panicButton = true,
             zoneType = 'box', coords = { x = -1194.1, y = -899.4, z = 13.9 },
             size = { x = 2.0, y = 1.2, z = 1.5 }, rotation = 34.0 },
           { moduleType = 'Stash', label = 'Walk-in Fridge', id = 'burgershot_fridge', slots = 80, weight = 400000,
             zoneType = 'box', coords = { x = -1198.5, y = -896.0, z = 13.9 },
             size = { x = 1.5, y = 1.5, z = 2.0 }, rotation = 34.0 },
           { moduleType = 'Crafting', label = 'Grill',
             recipes = { 'bs_beef', 'bs_slicedonion', 'bs_slicedpotato', 'bs_burger', 'bs_fries' },
             zoneType = 'box', coords = { x = -1197.0, y = -900.5, z = 13.9 },
             size = { x = 2.5, y = 1.2, z = 1.5 }, rotation = 34.0 },
           { moduleType = 'SalesItems', label = 'Sales items',
             items = { 'burger', 'fries', 'water_bottle', 'sprunk' } },
           { moduleType = 'BossMenu', label = 'Manager Desk',
             zoneType = 'sphere', coords = { x = -1200.5, y = -894.0, z = 13.9 }, radius = 1.0 },
       },
   }
   ```

3. **Give it recipes and stock** — Create business-specific recipes on the business's Recipes page; shared recipe ids from `Config.recipes` (`shared/recipes/*.lua`) can be referenced by any business. Choose what staff may sell on the Sales Items page. A `POS` module may also reference shop-item list names from `Config.shopItems` (`shared/shopitems/*.lua`) to fix closed-shop prices.

   ```lua title="shared/recipes/burgershot.lua + shared/shopitems/burgershot.lua"
   -- shared/recipes/burgershot.lua — one recipe, referenced by id from any bench.
   Config.recipes['bs_burger'] = {
       label = 'Bleeder burger', time = 6000, progressLabel = 'Building a burger',
       completeLabel = 'One Bleeder, ready to go.',
       anim = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle', flag = 1 },
       ingredients = {
           { item = 'beef', amount = 1 }, { item = 'slicedonion', amount = 1 }, { item = 'bun', amount = 1 },
       },
       give = { { item = 'burger', amount = 1 } },
       levelRequired = { { skill = 'cooking', level = 2 } },   -- only enforced when Config.skills.enabled
       xpGained = { { skill = 'cooking', xp = 10 } },
   }

   -- shared/shopitems/burgershot.lua — a till's stock list. Prices with `price` are FIXED;
   -- an entry with no price is employee-priced on first restock, then remembered.
   Config.shopItems['burgershot'] = {
       { item = 'burger', price = 12 },
       { item = 'fries', price = 8 },
       { item = 'water_bottle', price = 5 },
       { item = 'sprunk' },   -- no price: employee sets it on first restock
   }
   ```

4. **Delete it if you would rather build from scratch** — Seed files are optional worked examples. Remove `shared/businesses/burgershot.lua` (and its matching recipe/shop-item files, if unused elsewhere) and nothing is created; `/jobcreator` builds the same structure in-world without any file.

## The crafting flow, precisely

This is the part most worth reading carefully: the proximity check and the ingredient-refund behavior described here reflect a recent fix and are the current, verified behavior of the code in this resource.

- Each crafting category (or a single bench's `recipes` list) holds recipe **ids**, not recipes. The server looks up the id in the business's SQL recipe library first, then in the shared `Config.recipes`. The client never sends recipe data — only the business, module, category and recipe IDs — so clients cannot supply their own ingredients or outputs.
- Server-side order in `Kora.callback.register('kora_jobcreator:server:craft', ...)` (`server/crafting.lua`): (1) the business and module must exist and the module must be a `Crafting` module; (2) the caller must work the business's job; (3) the recipe id must be assigned to the selected category; (4) the caller must be near one of that category's saved locations (or the single bench's anchor); (5) `Crafting.craft` checks skill, ingredients, and capacity before changing inventory. Categories hold their own recipe arrays and location arrays, so each bar, prep table, or grill opens the matching set of recipes.
- **Crafting.craft** (shared by the bench callback and `UseableItem` recipe-type useables): checks `levelRequired` when `Config.skills.enabled`; rejects if the recipe produces nothing; checks the caller holds enough of every ingredient and has room for every output; double-checks combined capacity with `exports.kora_inventory:CanCraftItems`; then removes ingredients one at a time and finally adds every output one at a time.
- **Ingredient refund**: if removing an ingredient fails partway through, every ingredient already removed in that craft is refunded. If granting the output fails after ingredients were removed, the server refunds those ingredients too. On success, `xpGained` is awarded when `Config.skills.enabled`, and the craft is logged as a `craft` category entry.
- A **`UseableItem`** module (consumed from the inventory, no world anchor, `server/crafting.lua` → `Crafting.registerUseable`) either runs a `recipe` (same `Crafting.craft` path, business-logged) or rolls a `rewards` pool with `Kora.rewards.generate({ mode = 'weighted', rolls })`. The item is consumed up front and refunded if the outcome fails for any reason (recipe gone, inventory full, nothing could be carried).

## Permissions model

- **Admin**: `State.isAdmin(src)` is `exports.kora_core:hasPermission(src, Config.adminPermission)` (default permission string `'admin'`). Admin is required to create, rename/reassign or delete a business, and to add, edit or remove any module (`authorise(src, businessId, true)` in `server/admin.lua`).
- **Boss**: `State.isBoss(src, job)` checks the caller's current job equals the business's job AND their job grade has `isboss = true` in that job's definition. `State.canManage` is `isAdmin OR isBoss`; it gates read-only business management (viewing logs/balance, opening the management console, setting till prices) but NOT the admin-only mutations above.
- **Employee**: `State.worksFor(src, job)` is true for ANY grade of that job (not just boss). `State.employeeAt(src, business, module?, requireDuty?)` is the shared gate for presence-sensitive actions: it requires the caller's job to match, optionally requires on-duty, and requires proximity — to the given module if one is passed, otherwise to any of the business's `Zone` modules (`State.nearBusiness`).
- Nothing here is purely a UI convenience: every one of these checks is re-run server-side inside the callback that performs the action, independent of what the client's NUI happened to show or gate.

## Replication and live editing

The server is the only writer. Every business definition is fingerprinted (`business.rev`, an FNV-1a hash of its label/job/modules) and broadcast whole to every client on any change (`kora_jobcreator:client:sync`). A client only rebuilds a business whose `rev` changed, so editing one business does not make every other player-occupied business in the world flicker. Module webhook URLs are a server-only credential and are stripped from every client-facing snapshot (`State.snapshot()` without `includePrivate`).

## Till economics: tax, commission, payment commission

- A **closed-shop sale** (customer buys from the shelf): credited from `kora_inventory`'s own post-commit purchase audit event, never from a pre-commit hook — a hook fires before the purchase is locked in, so crediting there could pay out for a sale that still fails on weight, funds or a stale revision. `Config.pos.closedShopCut` (default 20%) of the gross price is withheld and not paid to anyone; the rest is credited to the business account. A closed shop pays no sales tax or sold-stock commission. A staffed till has no customer shelf at all; it sells through item sales (below).
- A **restock** (employee drops items in the intake stash and closes it): prices are resolved per item name ONCE (asking a price yields, and the stash can change under a yield, so pricing happens first and the actual shelf move runs to completion afterwards without yielding). An item with no fixed price and no remembered price prompts the employee in Appshell (capped at `Config.pos.maxPrice`); the chosen price is then remembered for every future restock of this item at that till. Items the closed shop does not accept are left in the stash and the employee is told so: when the business has a non-empty Sales Items list, only those items are accepted; otherwise the till's `Config.shopItems` lists (if any) decide.
- An **item sale** (from a till's Take a payment option or the portable `cardmachine` item): the employee selects items from the business Sales Items list, sees their carried quantity, and enters quantities and unit prices in Appshell. They choose the buyer from the nearby player list, including themselves. The buyer reviews the itemized invoice and chooses cash or card, then accepts or declines. The server rechecks the Sales Items list, seller inventory, buyer funds and distance between different players; it removes the items and charges the buyer only after approval. `Config.payment.commission` (default 10%) goes to the employee's bank and the remainder goes to the business account. If charging or business credit fails, the resource attempts to restore items and refund the buyer.
