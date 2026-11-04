# kora_jobcreator

An in-game, kora_lib-native job and business creator. A business is a
job, a perimeter, and a stack of **modules** — a till, a stash, a crafting
bench, a boss desk, a prop — and every one of them is built in-game and stored
in MySQL. There is no config file to edit, no snippet to paste, and no restart:
what you build appears for every player on the server as you build it.

Inspired by [`jay-businesses`](https://github.com/Jay60Dev/jay-businesses),
rewritten from scratch on kora_lib / kora_core / kora_sql / kora_inventory / kora_target.

kora_lib owns the application shell, forms, menus, notifications, callbacks,
database access, configuration, shared registries, interactions, zones,
placement, raycasts, progress, entities, blips, animation, logging, Discord
delivery, rewards, and proximity checks. kora_target is used directly only for
polygon interaction zones, which kora_lib does not currently expose.

---

## Install

1. Drop `kora_jobcreator` into your resources folder.
2. Start it **after** `kora_lib`, `kora_sql`, `kora_core`, `kora_inventory` and `kora_target`:

```cfg
ensure kora_jobcreator
```

The tables are created automatically at startup. `kora_bossmenu` (business bank account)
and `kora_dispatch` (panic button) are optional — the resource starts and runs
without either, and says so when you try to use a feature that needs one.

A demo **Burger Shot** is seeded on first boot so there is something to look at,
along with the `burgershot` job it needs — registered only if your server does
not already define one. Delete the business in-game and it stays deleted; seeds
never come back.

---

## Building a business

`/jobcreator` — admins see everything, a boss sees their own business.

```
Job Creator
  Businesses                   -> searchable business cards
  Burger Shot                  -> Overview / Modules / Activity
```

The console is a registered kora_lib AppShell app. Actions and forms stay in the
selected business workspace. Every coordinate or placement action declares
`closeBeforeAction`, so kora_lib closes the shell and releases its focus lease
before the world editor starts. When capture finishes (or is cancelled), the
creator reopens AppShell on the same business, tab, and selected module with
the returned coordinates applied.

Adding a module asks three things: **what** it is, **where** it is, and whether
it wants a map blip. "Where" is never typed in:

| Anchor | Tool |
|---|---|
| Sphere / box / poly zone | kora_lib's in-world zone creator — fly, aim, place, scroll to size |
| Prop / ped / vehicle | kora_lib's placement tool — position it, then confirm |
| An object already there | Look at it and press `E`; a box zone is fitted to its model |

Saving pushes the row to MySQL and the new definition to every connected
client. The till exists for everyone about two frames later.

Each module card has two editing paths. **Edit data** opens the current module
as prefilled JSON, so an admin can change labels, access, prices, recipes, or
advanced anchor values without placing it again; the normal schema validation
still applies on save. **Rebuild** is for changing a module's type or placing a
fresh world anchor. The admin-only **Debug** tab can copy the current business
or selected module JSON and toggle zone/target outlines on that administrator's
client only.

Crafting benches select all offered recipes in one multiselect field. The
server still resolves and validates those recipe ids against the shared recipe
library before saving the module.

---

## Modules

| Module | What it does |
|---|---|
| **Zone** | The business perimeter. Entering builds everything below and clocks staff on; leaving tears it down and clocks them off. |
| **Blip** | A map marker. |
| **StaticEntity** | Decorative props, peds or vehicles with no interaction. |
| **BossMenu** | Opens `kora_bossmenu` for a boss of this job. |
| **POS** | A customer-facing till, an employee-facing intake stash, prices, tax, sold-stock commission and an optional panic button. |
| **Stash** | Job-locked storage. |
| **Crafting** | A bench offering recipes from the shared recipe library, with live ingredient counts and optional skill gates. |
| **UseableItem** | Binds an item to a weighted reward roll or to a recipe — mystery boxes, ingredient packs. |

Every module with a world anchor may be a **zone** or an **entity**, may carry
its own blip, and may be marked `public` to drop its job lock.

### How a till works

Stock is **not** stored by this resource — kora_inventory already owns a shop
inventory and persists it, and a second copy of the same shelf is exactly the
bug worth avoiding. What this resource owns is the policy around it.

```
employee                          customer
   |                                  |
   v                                  v
[intake stash] --close--> [shelf] --buy--> money
                            ^                |
                     price policy      minus tax -> business account
```

* An employee drops goods in the **intake stash**. Closing it moves everything
  onto the shelf in one go — one price prompt per item type, not one per drag.
* A price comes from the till's `Config.shopItems` list if that list fixes one,
  otherwise from what the till was last told, otherwise the employee is asked.
  What they answer is remembered for next time.
* A **sold-stock commission** (`%` of committed sale revenue) is attributed to
  the employee who stocked that batch. Merely stocking or naming a price pays
  nothing. When a customer actually buys it, the business receives the sale and
  the online stocker is paid from that revenue.
* A sale credits the business account with the price minus **tax**, and is
  credited from kora_inventory's committed purchase record — never from a
  pre-commit hook, which would pay out for sales that then fail.
* `hideWhenStaffed` stops customers self-serving while an employee is inside.
  Staff presence means an on-duty employee whose live server position remains
  inside the configured business perimeter.

### The card machine

Anyone carrying `Config.payment.item` (default `cardmachine`) can target a
player and bill them. The employee names the amount, the customer approves it,
the customer's bank is debited, the employee keeps a commission and the rest
goes to the business account. The distance between the two is re-checked
**after** both dialogs — walking away mid-transaction cancels it — and if the
business account turns out to be unreachable the customer is refunded rather
than the money vanishing.

---

## Configuration

`config.lua` holds policy: permissions, defaults, rates, webhooks, and the
optional skill adapter. Business *definitions* are not configured there.

* `shared/recipes/*.lua` — the recipe library. Written once, referenced by id
  from any number of benches.
* `shared/shopitems/*.lua` — named item lists a till may reference. An entry
  with a `price` is fixed at that price; one without is employee-priced.
* `shared/businesses/*.lua` — first-boot seeds. Inserted only when no business
  with that id exists and it has not been deleted in-game. Deletion markers in
  `kora_jobcreator_deleted` prevent reseeding; admins can still explicitly recreate
  the same id. In-game edits and deletions always win. A seed may
  also carry a `jobDefinition`, registered at boot when no job of that name
  exists yet — kora_core's job registry is in-memory, so this is re-checked every
  start, and a server that defines its own version of the job always wins.

### Skills

Off by default. `Config.skills.enabled = true` turns on the `levelRequired` and
`xpGained` fields on recipes, using `getLevel`/`addXp` adapters that default to
kora_core metadata. Point them at your own skill resource if you have one.

### Discord

`Config.webhooks.default` receives every business event; a `[jobname]` key
receives that job's as well, and a POS module may name a third URL of its own.
All of it also lands in `kora_jobcreator_logs` and in kora_lib's own event log
regardless of whether any webhook is configured.

Webhook URLs are omitted from client definitions and copied public module data.
The admin data editor retrieves the full module after a server permission check,
so unrelated edits retain its saved webhook. Server exports retain full definitions.

---

## Exports

```lua
-- server
exports.kora_jobcreator:getBusinesses()             -- every definition
exports.kora_jobcreator:getBusiness(id)
exports.kora_jobcreator:getBusinessesByJob(job)     -- ids
exports.kora_jobcreator:getStaffCounts()            -- businessId -> staff inside
exports.kora_jobcreator:recordBusinessLog(id, category, message, amount)

-- client
exports.kora_jobcreator:getBusinesses()
exports.kora_jobcreator:openBusinessMenu()
```

---

## Tables

| Table | Holds |
|---|---|
| `kora_jobcreator` | One row per business: label, job, and its modules as JSON. |
| `kora_jobcreator_deleted` | Deleted business IDs, retained to prevent automatic reseeding. |
| `kora_jobcreator_prices` | Employee-set prices, remembered per till and item. |
| `kora_jobcreator_logs` | Sales, restocks, payments, crafts and admin edits. |

Shop stock and stash contents live in kora_inventory's own tables.

---

## Tests

```sh
test/run.sh          # LUA=lua5.4 test/run.sh to pick an interpreter
```

Plain Lua, no FiveM and no database. The schema is exercised for real; the
server and client files are checked against the invariants that matter —
authorisation, rate limits, rollbacks, and the threading rules around kora_lib's
shared zone tick and kora_target's shared target loop.
