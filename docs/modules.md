---
title: Modules
sidebar_position: 6
---

# Modules

Every module is plain JSON. All modules are validated by `shared/schema.lua` before they are saved or replicated; an invalid module is rejected (when loading from the database, it is skipped with a console warning and the rest of the business still loads).

## Common fields

| Field | Type | Notes |
| --- | --- | --- |
| `moduleType` | string | Required. One of the types below. |
| `label` | string | Up to 64 characters. Defaults to the type's label (for a Blip, to its `name`). |
| `icon` | string | Icon key for the target option, up to 48 characters. |
| `public` | boolean | Removes the job lock from supported module target options and server checks, such as stash access. Crafting and employee stores always require the player's job to match the business. |
| `distance` | number | Interaction distance, 0.5 to 20, default 2.0. |
| `blip` | table | Optional. `enabled`, `category`, `name`, `sprite` (0-900), `color` (0-90), `scale` (0.1-3), `display` (0-11), `shortRange`, `coords`. `category` must be a category known to `Kora.blips.getCategoryIds()` and defaults to `Business`. Without `coords` the module's own anchor is used. A legacy `label` is accepted as `name`. `enabled = false` drops it. |

## Anchors

Each type accepts a zone anchor, an entity anchor, both or neither:

| Type | Anchor |
| --- | --- |
| Zone | zone only |
| Blip | none |
| StaticEntity | entity only |
| BossMenu, POS, Stash | zone or entity |
| Crafting | zone or entity for a single bench; none for a crafter with categories (each category carries its own locations) |
| UseableItem, SalesItems | none |

**Zone** - `zoneType` is `sphere`, `box` or `poly`.

| `zoneType` | Fields |
| --- | --- |
| `sphere` | `coords`, `radius` (0.1-100, default 1.5) |
| `box` | `coords`, `size` with `x`, `y`, `z` (each 0.05-200, required), `rotation` (default 0) |
| `poly` | `points` (3 to 64 points), `thickness` (0.1-100, default 4.0), `coords` (anchor used for blips and distance checks) |

**Entity** - `model` with `model` (name), `modelType` (`ped`, `object` or `vehicle`, default `object`), optional `existing`, `anim` (`dict`, `clip`, `flag`, applied to peds) and `freeze`; plus `coords`, an array of up to 32 positions. `existing = true` adopts a matching object within 1.5 m instead of spawning one. Coordinates are `x`, `y`, `z` and optional `w` heading.

## Types

### Zone

The business perimeter. `controlDuty` (default `true`) clocks staff on when they enter and off when they leave (also subject to `Config.duty`). If a business has a Zone, all other modules except Zone and Blip are built only while the player is inside it and torn down on exit. A business with no Zone builds everything as soon as it is known.

### Blip

A map marker: `coords` (required), `category` (default `Business`), optional `name`, `sprite`, `color`, `scale`, `display`, `shortRange`. Always built at startup.

### StaticEntity

A decorative prop, ped or vehicle. No interaction.

### BossMenu

Adds a target option that calls `openBossMenu` on `kora_bossmenu`. Only shown to a boss of the business job (the grade has `isboss`).

### POS

A point-of-sale fixture. Create one from the **Tills** page (or Modules → Add module) and change its settings there later without moving it.

- A **staffed till** (the default) is where employees take itemized payments: "Take a payment" opens the Appshell sale builder over the business's Sales Items. See [Card machine](#card-machine).
- A **closed shop** (`closedShop = true`) is a customer shelf. Staff restock it; customers may browse only while no on-duty employee is in the business. It requires a business Zone.

| Field | Notes |
| --- | --- |
| `id` | Required. Shop id, slugged. Two modules in the same business may share an id (a row of registers); the first registration owns the policy. An id already used by another business is refused with a console warning. |
| `closedShop` | `true` for a closed shop. Saving one in a business without a Zone is refused. Default `false`. |
| `items` | Closed shops only. Names of `Config.shopItems` lists. When the business has a non-empty Sales Items list, that list decides what is accepted and these lists only fix prices; otherwise these lists restrict what may be stocked and fix prices. Omit to let staff set every price. |
| `panicButton` | Adds a "Panic button" option for on-duty employees. |
| `currency` | `cash` or `bank`, default `Config.pos.currency`. The account closed-shop customers pay from. |
| `shopSlots`, `stockSlots` | 1 to 500, default from `Config.pos`. |
| `webhook` | Discord URL for this till's log entries, in addition to the job and default webhooks. Never sent to clients. |
| `commission`, `tax`, `hideWhenStaffed` | Still validated (percentages outside 0 to 100 are rejected) but no longer used: staffed tills have no shelf, and closed shops always apply the staffing rule and `Config.pos.closedShopCut`. |

Target options:

| Option | Staffed till | Closed shop | Who |
| --- | --- | --- | --- |
| Take a payment | yes | yes | Employees (no card machine item needed) |
| Panic button | if `panicButton` | if `panicButton` | Employees |
| Browse shop | no | yes | Anyone while no staff are in; staff always |
| Restock | no | yes | Employees |
| Set prices | no | yes | Boss, near the till |

Closed-shop restocking: an employee drops goods into the intake stash (`<id>_stock`) and closes it. Accepted items move onto the shelf; the rest stay in the stash. A price is requested once per item type when there is no fixed or remembered price (up to `Config.pos.maxPrice`); a boss can later change non-fixed prices with "Set prices". On a committed purchase, `Config.pos.closedShopCut` (default 20%) is withheld and the remainder is credited to the business account. There is no sales tax and no sold-stock commission.

Intake and the stock stash are job-locked regardless of `public`. Till and stash inventories are registered with `kora_inventory` using the module's coordinates and an interaction radius that covers the zone shape plus `distance`.

### Stash

`id` (required, slugged), `slots` (1-500, default `Config.stash.slots`), `weight` (1000 to 100000000 grams, default `Config.stash.weight`). Create one from the **Stashes** page (or Modules → Add module); its label, slots, weight and access can be changed there later and its contents are kept. Use Modules → Rebuild to move it. Job-locked unless `public`. A stash id already used by another business is refused with a console warning. Contents are stored by `kora_inventory`.

### Crafting

Two shapes, both managed from the **Crafters** page:

- **Crafter with categories** (no anchor). `crafters` is a list of up to 32 categories, each `{ id, label, recipes, locations }`. `id` is derived from the label and kept when the label changes. `recipes` is a list of up to 100 recipe ids. `locations` is a list of up to 16 points `{ x, y, z, w, model? }`; `model` is set when the admin required aiming at a specific prop while placing it. Each location becomes a target that opens that category's recipe menu on the right of the screen, with the output item's image. A new crafter may have no categories yet.
- **Single bench** (zone or entity anchor, made with Modules → Add module). `recipes` is a non-empty list of recipe ids, all offered at the bench's anchor.

Recipe ids resolve to the business's own recipes (Recipes page) first, then `Config.recipes`. The menu shows ingredient counts and disables recipes the player cannot make; a progress bar runs if the recipe has a `time`. The server then checks that the player works the job (`public` does not apply), that the recipe belongs to the chosen category, that the player is near one of its locations, skill requirements (when enabled), ingredients and room. See [Crafting](./api/crafting.md).

### SalesItems

One per business, built from the **Sales Items** and **Stores** pages and hidden from Modules → Add module. A second one is refused.

| Field | Notes |
| --- | --- |
| `items` | Up to 200 item names staff may sell through itemized payments. Also what a closed shop accepts when non-empty. |
| `stores` | Up to 32 employee stores, each `{ id, label, payFrom, items, locations }`. |
| `stores[].payFrom` | `player` (default; charged from `Config.stores.account`) or `business` (debited from the business account through `kora_bossmenu`). |
| `stores[].items` | Up to 100 `{ item, price }` entries; `price` is 0 to `Config.pos.maxPrice`. |
| `stores[].locations` | Up to 16 points, placed like crafter locations. |

A store location shows "Browse (store)" to employees. The Appshell catalog lists its items and prices; the employee enters a quantity (up to `Config.stores.maxQuantity`) and receives the items. Supply is unlimited and no `kora_inventory` shop or stock count is used. The server checks job, proximity to one of the store's locations, the saved price and carrying capacity, and logs the pickup as `stock`. See [Recipes and stores](./api/job-recipes.md).

### UseableItem

Binds an item to a use handler. No anchor.

| Field | Notes |
| --- | --- |
| `item` | Required, lower-cased. Bound once; if another business already holds the binding, a `register.item_handler_exists` warning is logged and the second is not bound. |
| `consume` | Items taken per use, 0 to 100, default 1. Refunded if the outcome fails. |
| `useType` | `reward` (default) or `recipe`. |
| `rewards` | For `reward`: non-empty list of `item` (or `name`), `amount` (1-1000, default 1), `chance` (relative weight, default 1). |
| `rolls` | For `reward`: picks per use, 1 to 20, default 1. Uses `Kora.rewards.generate` in weighted mode. |
| `recipe` | For `recipe`: id from the business's Recipes page or `Config.recipes`. The pickers list both. |

Anyone with the item can use it; there is no job check.

## Card machine

The till's "Take a payment" option opens the Appshell sale builder. The portable player target is also available to employees holding `Config.payment.item`; it opens the same sale builder with the targeted customer prefilled. The seller sees items selected in Sales Items, their on-hand quantities and images. The seller selects quantities and enters each unit price, then chooses the buyer from the player list. The buyer may be the seller.

The buyer reviews the invoice and chooses cash, card, or decline. The server rechecks the catalog, seller inventory, buyer funds, and distance between different players. Cash debits the buyer's `cash` account; card debits `bank`. The seller's items are removed only when the approved payment can complete. The employee receives `floor(total * Config.payment.commission)` in their bank and the remainder is credited to the business account. If charging or business credit fails, the resource attempts to restore the items and refund the buyer.

Only items on the business's Sales Items list and currently carried by the seller can be sold. The employee enters a unit price for each selected item because Sales Items does not store retail prices. A sale is capped at `Config.payment.maxAmount`. One sale per employee and one invoice per buyer may be in flight at a time.
