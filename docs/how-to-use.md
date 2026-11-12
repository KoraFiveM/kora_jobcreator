---
title: "How to use"
sidebar_position: 3
---


# How to use

Kora Job Creator separates WHAT a business is made of (modules, recipes, shop lists — this resource's schema) from WHERE it physically lives (placed in-game, never hand-authored coordinates). Read this page before adding a business; the burgershot seed is the shape every concept below refers to.

## Business and module concepts

- A **business** is `{ id, label, job, modules[] }`. `id` is a slug (lowercase, punctuation stripped) and the primary key; `job` is the kora_core job name staff and tills are gated by. Every mutation (`createBusiness`, `editBusiness`, `saveModule`, `removeModule`, `deleteBusiness`) re-validates and re-persists the WHOLE business as one row — there is no partial update path — so a rejected edit always leaves the database and the live server exactly as they were.
- A **module** is one placed thing: `Zone` (perimeter), `Blip`, `StaticEntity` (decorative prop/ped), `BossMenu`, `POS` (till), `Stash`, `Crafting` (bench) or `UseableItem` (server-only, no world anchor). Each module type declares what kind of world anchor it accepts via `interaction`: `zone` (trigger volume only), `model` (a spawned or adopted entity), `any` (builder's choice) or `none`.
- A module anchor is either a **zone** (`sphere`, `box` or `poly`, with `coords`/`radius`/`size`+`rotation`/`points`+`thickness`) or one or more **model** coordinates (`{ model, modelType, existing?, anim?, freeze? }` placed at up to 32 points — a till row of several identical registers is one module). `S.normaliseModule` in `shared/schema.lua` is the ONE validator for both realms: the server runs it before anything is written or broadcast, and the client re-runs it on receipt so a malformed module only skips itself instead of failing the whole business.
- **Startup vs. dynamic**: if a business has a `Zone` module, every other module is built lazily when a player enters that zone and torn down when they leave (a server with fifty businesses does not hold fifty tills' worth of props and target registrations at once). `Zone` and `Blip` modules are always "startup" (built immediately). A business with NO `Zone` module has nothing to trigger lazy building, so every one of its modules is treated as startup instead.
- `public` on a module skips the job lock for its target options (used for a shop's "Buy" option, which must never require the business's own job). `hideWhenStaffed` on a `POS` module additionally hides the customer "Buy" option while staff are present.

## Adding a new business

1. **In-game (recommended)** — Run `/jobcreator` (`Config.command`). An administrator sees the full business directory with a "Create business" action (name + an existing kora_core job); anyone with a boss grade sees only the businesses they manage. Creating a business leaves it with zero modules and immediately opens the module editor to place its first `Zone`. Placing a zone or an entity anchor hands off to kora_lib's in-world zone creator / prop placer / camera raycast ("use what is already there") — coordinates are never typed in by hand.

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
           { moduleType = 'BossMenu', label = 'Manager Desk',
             zoneType = 'sphere', coords = { x = -1200.5, y = -894.0, z = 13.9 }, radius = 1.0 },
       },
   }
   ```

3. **Give it recipes and stock (optional, shared libraries)** — A `Crafting` module references recipe ids from `Config.recipes` (populated by `shared/recipes/*.lua`); a `POS` module references shop-item list names from `Config.shopItems` (populated by `shared/shopitems/*.lua`). Both are keyed, reusable libraries — write a recipe or a price list once and point any number of benches or tills at it.

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

- A bench lists recipe **ids**, not recipes: `Config.recipes[id]` is the single shared library (`shared/recipes/*.lua`), so two businesses that both grill beef reference the same definition. The client never sends a recipe — only a business id, a module index and a recipe id — and the server looks the recipe up itself; a client that lies about any of the three is rejected, not given a recipe of its own design.
- Server-side order in `Kora.callback.register('kora_jobcreator:server:craft', ...)` (`server/crafting.lua`): (1) the business and module must exist and the module must be a `Crafting` module; (2) unless the module is `public`, the caller must work the business's job; (3) the recipe id must be one this specific bench's `recipes` list actually offers — not merely a recipe that exists anywhere; (4) **proximity** — `State.nearModule(src, module)` must return true, or the call fails with `'You are not at the bench.'`; (5) `Crafting.craft` runs the transaction.
- **Proximity check (current behavior, recently fixed)**: `State.nearModule` derives its boundary from `State.moduleBoundary(module)`, which returns EVERY coordinate a module was placed at (a bench module can anchor several physical locations — several grills) plus one shared radius, and checks the caller's distance against each of those points in turn, succeeding if any one matches. This is now used uniformly for every configured crafting-bench location. Previously only the bench's first configured location was checked, which meant a bench placed at multiple spots was only usable from the first one; that has been corrected so all of a bench's locations work.
- **Crafting.craft** (shared by the bench callback and `UseableItem` recipe-type useables): checks `Config.skills` level requirements (only when `Config.skills.enabled`); rejects if the recipe produces nothing; checks the caller holds enough of every ingredient and has room for every output; double-checks combined capacity with `exports.kora_inventory:CanCraftItems`; then removes ingredients one at a time and finally adds every output one at a time.
- **Ingredient refund (recently fixed), two layers**: if removing an ingredient fails partway through, every ingredient already removed in that same craft is refunded immediately (this existed before). What was ADDED: if every ingredient was removed successfully but granting a produced item then fails (inventory full etc.), every ingredient that was removed for this craft is now refunded back to the player — `CanCraftItems` already checked combined capacity so this should not normally happen, but if it does the player is no longer left having paid ingredients for nothing. On success, `Config.skills.enabled` awards `recipe.xpGained`, and the craft is logged as a `craft` category entry.
- A **`UseableItem`** module (consumed from the inventory, no world anchor, `server/crafting.lua` → `Crafting.registerUseable`) either runs a `recipe` (same `Crafting.craft` path, business-logged) or rolls a `rewards` pool with `Kora.rewards.generate({ mode = 'weighted', rolls })`. The item is consumed up front and refunded if the outcome fails for any reason (recipe gone, inventory full, nothing could be carried).

## Permissions model

- **Admin**: `State.isAdmin(src)` is `exports.kora_core:hasPermission(src, Config.adminPermission)` (default permission string `'admin'`). Admin is required to create, rename/reassign or delete a business, and to add, edit or remove any module (`authorise(src, businessId, true)` in `server/admin.lua`).
- **Boss**: `State.isBoss(src, job)` checks the caller's current job equals the business's job AND their job grade has `isboss = true` in that job's definition. `State.canManage` is `isAdmin OR isBoss`; it gates read-only business management (viewing logs/balance, opening the management console, setting till prices) but NOT the admin-only mutations above.
- **Employee**: `State.worksFor(src, job)` is true for ANY grade of that job (not just boss). `State.employeeAt(src, business, module?, requireDuty?)` is the shared gate for presence-sensitive actions: it requires the caller's job to match, optionally requires on-duty, and requires proximity — to the given module if one is passed, otherwise to any of the business's `Zone` modules (`State.nearBusiness`).
- Nothing here is purely a UI convenience: every one of these checks is re-run server-side inside the callback that performs the action, independent of what the client's NUI happened to show or gate.

## Replication and live editing

The server is the only writer. Every business definition is fingerprinted (`business.rev`, an FNV-1a hash of its label/job/modules) and broadcast whole to every client on any change (`kora_jobcreator:client:sync`). A client only rebuilds a business whose `rev` changed, so editing one business does not make every other player-occupied business in the world flicker. Module webhook URLs are a server-only credential and are stripped from every client-facing snapshot (`State.snapshot()` without `includePrivate`).

## Till economics: tax, commission, payment commission

- A **sale** (customer buys from the shop): credited from `kora_inventory`'s own post-commit purchase audit event, never from a pre-commit hook — a hook fires before the purchase is locked in, so crediting there could pay out for a sale that still fails on weight, funds or a stale revision. `tax` (module-level, 0–100%) is deducted from the gross price before anything else; `commission` (module-level, 0–100%) is then paid, but ONLY to the citizenid that is still attached as the stocker of that exact shelf slot at sale time (attribution is server-only metadata set at intake, never a client-supplied field) — a slot whose stock came from kora_inventory directly, or outlived its stocker, pays no commission. The remainder goes to the business account via `exports.kora_bossmenu:addBusinessMoney`.
- A **restock** (employee drops items in the intake stash and closes it): prices are resolved per item name ONCE (asking a price yields, and the stash can change under a yield, so pricing happens first and the actual shelf move runs to completion afterwards without yielding). An item with no fixed price and no remembered price prompts the employee with a dialog (capped at `Config.pos.maxPrice`); the chosen price is then remembered for every future restock of that item at that till. Items this till does not stock (per its `Config.shopItems` list, if it has one) are left in the stash and the employee is told so.
- A **card payment** (portable `cardmachine` item, any business, not tied to a till): the employee names an amount, the customer independently approves it, distance between the two is re-checked AFTER both dialogs (a player can walk away mid-dialog), the customer is charged, `Config.payment.commission` (default 10%) goes straight to the employee's bank, and the remainder goes to the business account. If crediting the business account fails, the customer is refunded and the employee's commission is reversed — nobody is left holding a payment that did not complete.
