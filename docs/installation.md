---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Job Creator is the in-game job and business builder for the Kora stack: zones, blips, tills, stashes, crafting benches and useable items are composed from modules an admin places in-world or a server defines as a first-boot seed, validated by one shared schema, persisted to the database, and replicated to every client. It still answers to the legacy export name `kora_jobcreator`. Follow these steps in order.

## Install Kora Job Creator

1. **Add the folder** — Place `kora_jobcreator` in your resources directory (on the Kora recipe it is `resources/[kora]/kora_jobcreator`).

2. **Start its dependencies first** — It declares `dependency` on `kora_lib`, `kora_sql`, `kora_core`, `kora_inventory` and `kora_target`. Start all five, and `kora_sql`, before `ensure kora_jobcreator`.

   ```bash title="server.cfg"
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_inventory
   ensure kora_target
   ensure kora_jobcreator
   ```

3. **Load order inside the resource** — The manifest's own script order is deliberate and should not be reordered if you fork it: shared scripts load `config.lua` → `shared/schema.lua` → the reusable `recipes`/`shopitems`/`businesses` libraries → `shared/config_registration.lua` last, so the config-adoption bridge sees every static value those files added. On the server, `state.lua` (owns the in-memory registry) loads before everything that reads it, and `main.lua` (the boot sequence) loads last.

   ```lua title="fxmanifest.lua" {20,21,22,23,24,25,26}
   fx_version 'cerulean'
   game 'gta5'
   lua54 'yes'

   name 'kora_jobcreator'

   dependency 'kora_lib'
   dependency 'kora_sql'
   dependency 'kora_core'
   dependency 'kora_inventory'
   dependency 'kora_target'

   shared_scripts {
       '@kora_lib/init.lua',
       '@kora_core/init.lua',
       'config.lua',
       'shared/schema.lua',
       'shared/recipes/*.lua',
       'shared/shopitems/*.lua',
       'shared/businesses/*.lua',
       'shared/config_registration.lua',   -- must load last: it adopts the tables above
   }

   server_scripts {
       '@kora_sql/init.lua',
       'server/config.lua',
       'server/state.lua',   -- owns the registry every other server file reads
       'server/logs.lua',
       'server/staff.lua',
       'server/pos.lua',
       'server/crafting.lua',
       'server/payment.lua',
       'server/register.lua',
       'server/admin.lua',
       'server/tables.lua',
       'server/main.lua',    -- runs the boot sequence last
   }

   client_scripts {
       'client/state.lua',
       'client/business.lua',
       'client/payment.lua',
       'client/creator.lua',
       'client/main.lua',
   }
   ```

4. **Optional: boss-menu integration** — Till sales, card-payment proceeds and sold-stock commission all route through `exports.kora_bossmenu:addBusinessMoney` / `removeBusinessMoney` / `getBusinessBalance`. Without `kora_bossmenu` running, crediting a sale fails with `no business account resource is running` (logged, not thrown) and the boss console's Balance stat shows "Unavailable".

5. **Optional: panic buttons and skills** — A till's panic button needs `kora_dispatch` running (`exports.kora_dispatch:createCall`); without it the panic callback returns `false, 'No dispatch service is available.'`. Skill-gated recipes need `Config.skills.enabled = true` and a resource that implements `exports.kora_core:getMetaData/setMetaData` skill records (the default `config.lua` hooks already call that).

## Database schema

The schema (`server/tables.lua`, applied by `Kora.sql.ensureTables` on boot before anything else runs) creates four tables. Nothing here needs to be created by hand.

- `kora_jobcreator` — one row per business: `id` (primary key, varchar 64), `label`, `job` (indexed), `modules` (longtext JSON array of module definitions), `created_at`, `updated_at`. This is the single source of truth a business is rebuilt from on every boot and re-broadcast from.
- `kora_jobcreator_prices` — remembered POS prices: `(shop, item)` primary key, `price` (unsigned int). Populated the first time an employee restocks an item that has no fixed price, read back into memory by `Pos.loadPrices()` at boot.
- `kora_jobcreator_logs` — the per-business activity feed: auto-increment `id`, `business`, `category` (`sale`/`stock`/`payment`/`craft`/`admin`/`panic`), `message` (512 chars), `citizenid` (nullable), `amount` (nullable), `created_at`. Indexed on `(business, id)`. Trimmed to `Config.logs.retain` rows per business every 15 minutes.
- `kora_jobcreator_deleted` — a deletion tombstone: `id` primary key. An admin deleting a business inserts its id here so a seed with the same id is never silently resurrected on the next restart; explicitly recreating the same id is still honored.


## Requirements and optional resources

Declared with `dependency` in `fxmanifest.lua`:

| Resource | Used for |
| --- | --- |
| `kora_lib` | Callbacks, NUI app shell and dialogs, zones, interactions, blips, entities, progress bar, notifications, logging, Discord delivery, rewards, config registry |
| `kora_sql` | Table creation and all queries |
| `kora_core` | Player data, job and duty, permissions, items and money, shared job registry |
| `kora_inventory` | Shops, stashes, useable items, craft capacity checks |
| `kora_target` | Used directly only for polygon interaction zones and the global card-machine player option |

Used if present, not declared in the manifest:

| Resource | Used for |
| --- | --- |
| `kora_bossmenu` | Business account (`addBusinessMoney`, `removeBusinessMoney`, `getBusinessBalance`) and the boss menu module (`openBossMenu`) |
| `kora_dispatch` | Panic button (`createCall`) |

Both are checked with `GetResourceState(...) == 'started'` when needed. Without `kora_bossmenu`, till sales and card payments cannot credit a business account and the balance shows as unavailable. Without `kora_dispatch` the panic button replies that no dispatch service is available.

Tables are listed in [Database](./database.md); the first-boot seed is described in [Libraries and seeds](./libraries.md#seeds).
