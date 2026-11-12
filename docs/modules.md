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
| `public` | boolean | Removes the job lock from the module's target options and from server checks that honour it (stash, crafting). |
| `distance` | number | Interaction distance, 0.5 to 20, default 2.0. |
| `blip` | table | Optional. `enabled`, `category`, `name`, `sprite` (0-900), `color` (0-90), `scale` (0.1-3), `display` (0-11), `shortRange`, `coords`. `category` must be a category known to `Kora.blips.getCategoryIds()` and defaults to `Business`. Without `coords` the module's own anchor is used. A legacy `label` is accepted as `name`. `enabled = false` drops it. |

## Anchors

Each type accepts a zone anchor, an entity anchor, both or neither:

| Type | Anchor |
| --- | --- |
| Zone | zone only |
| Blip | none |
| StaticEntity | entity only |
| BossMenu, POS, Stash, Crafting | zone or entity |
| UseableItem | none |

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

A till.

| Field | Notes |
| --- | --- |
| `id` | Required. Shop id, slugged. Two modules in the same business may share an id (a row of registers); the first registration owns the policy. An id already used by another business is refused with a console warning. |
| `items` | Names of `Config.shopItems` lists. Restricts what may be stocked and fixes prices where a list gives one. Omit to allow any item at employee-set prices. An unknown list name logs a warning. |
| `commission` | 0 to 100 (percent). Default 0. |
| `tax` | 0 to 100 (percent). Default 0. |
| `hideWhenStaffed` | Customers cannot open the shop while an on-duty employee is inside the business perimeter. Staff of the job can always open it. |
| `panicButton` | Adds a "Panic button" option. |
| `currency` | `cash` or `bank`, default `Config.pos.currency`. |
| `shopSlots`, `stockSlots` | 1 to 500, default from `Config.pos`. |
| `webhook` | Discord URL for this till's log entries, in addition to the job and default webhooks. |

A percentage outside 0 to 100 is rejected (the module is not saved), not clamped.

Target options on a till: "Buy from (label)" (anyone, never job-locked), "Restock" (anyone working the job), "Set prices" (boss), "Take a payment" (anyone working the job; works without the card machine item), and "Panic button" when enabled.

How a sale works:

1. An employee drops goods into the intake stash (`<id>_stock`) and closes it. Closing moves everything the till accepts onto the shelf in one go, asking for one price per item type that has no fixed or remembered price (up to `Config.pos.maxPrice`). Items the till does not accept stay in the stash.
2. Prices come from a fixed price in the till's `Config.shopItems` list, otherwise from the remembered price in `kora_jobcreator_prices`, otherwise from the employee prompt. A boss can later change non-fixed prices with "Set prices".
3. On a committed purchase (the `purchase` audit event from `kora_inventory`) the business account is credited the price minus tax (`floor(price * tax / 100)`). If the stocker is online, a commission of `floor(price * commission / 100)` (capped at the net amount) is debited from the business account and paid to the stocker's bank. Stocking alone never pays.

Intake and the stock stash are job-locked regardless of `public`. Till and stash inventories are registered with `kora_inventory` using the module's coordinates and an interaction radius that covers the zone shape plus `distance`.

### Stash

`id` (required, slugged), `slots` (1-500, default `Config.stash.slots`), `weight` (1000 to 100000000, default `Config.stash.weight`). Job-locked unless `public`. A stash id already used by another business is refused with a console warning. Contents are stored by `kora_inventory`.

### Crafting

`recipes`: a non-empty array of ids from `Config.recipes`. The menu shows ingredient counts and disables recipes the player cannot make; a progress bar runs if the recipe has `time`. The server then checks that the business and module exist, that the player works the job (unless `public`), that the recipe is one this bench offers, that the player is near the module, skill requirements (when enabled), ingredients and room.

### UseableItem

Binds an item to a use handler. No anchor.

| Field | Notes |
| --- | --- |
| `item` | Required, lower-cased. Bound once; if another business already holds the binding, a console warning is printed and the second is not bound. |
| `consume` | Items taken per use, 0 to 100, default 1. Refunded if the outcome fails. |
| `useType` | `reward` (default) or `recipe`. |
| `rewards` | For `reward`: non-empty list of `item` (or `name`), `amount` (1-1000, default 1), `chance` (relative weight, default 1). |
| `rolls` | For `reward`: picks per use, 1 to 20, default 1. Uses `Kora.rewards.generate` in weighted mode. |
| `recipe` | For `recipe`: id from `Config.recipes`. |

Anyone with the item can use it; there is no job check.

## Card machine

Players holding the item in `Config.payment.item` get a "Take a payment" option on other players (`kora_target` global player type, distance `Config.payment.distance`). The till's "Take a payment" option asks for a server id instead. Flow:

1. The employee enters an amount (up to `Config.payment.maxAmount`).
2. The customer is asked to approve.
3. The server re-checks that both are within `Config.payment.distance`.
4. The customer's `Config.payment.account` is debited. The employee receives `floor(amount * Config.payment.commission)` in their bank and the remainder is credited to the business account of the employee's job.
5. If the business account cannot be credited, the customer is refunded and the employee's commission is taken back.

One payment per employee may be in flight at a time. The business used is the one whose `job` matches the employee's current job.
