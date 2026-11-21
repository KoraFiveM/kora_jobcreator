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
| `public` | boolean | Removes the job lock from supported module target options and server checks, such as stash access. Crafting always requires the player's job to match the business. |
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

A point-of-sale fixture. A normal till handles employee itemized payments; set `closedShop = true` for a customer-facing inventory shop.

The business-wide **Sales Items** page is independent of tills. It stores shared item names that the business offers, and every till accepts those items automatically. Items can be selected before any till exists. Store categories are employee-only Appshell pickup lists with configured prices and unlimited supply; they do not use a kora_inventory shop or finite stock.

The **Stores** page organizes shared ingredients into named store categories. Create a category, open it, add items from the shared catalog with a price, then use **Place store** to add one or more employee pickup locations. Staff open an Appshell catalog, enter a quantity, and receive the ingredient; supply is unlimited and no `kora_inventory` shop is used. Removing an item from the business-wide Sales Items page removes it from all store categories too.

| Field | Notes |
| --- | --- |
| `id` | Required. Shop id, slugged. Two modules in the same business may share an id (a row of registers); the first registration owns the policy. An id already used by another business is refused with a console warning. |
| `closedShop` | `true` for a Closed Shop. Requires a business Zone. Closed shops use the customer inventory-shop flow; normal tills do not show checkout or restock targets. |
| `items` / `saleItems` | Ignored for tills. The business-wide **Sales Items** page controls what may be stocked. |
| `commission` | 0 to 100 (percent). Default 0. |
| `tax` | 0 to 100 (percent). Default 0. |
| `hideWhenStaffed` | Always enabled; till access is employee-only. |
| `panicButton` | Always enabled. |
| `currency` | `cash` or `bank`, default `Config.pos.currency`. |
| `shopSlots`, `stockSlots` | 1 to 500, default from `Config.pos`. |
| `webhook` | Not configurable on tills. |

A percentage outside 0 to 100 is rejected (the module is not saved), not clamped.

Normal till target options: "Take a payment" (employees; works without the card machine item), "Set prices" (boss), and "Panic button" (employees, always enabled). Till targets do not show checkout or restock.

Closed Shops are managed on the **Closed Shops** page. Employees restock them from the business Sales Items and customers may browse only while no on-duty employees are in the business zone. Closed Shops have no sales tax or sold-stock commission; 20% of each sale's proceeds is withheld and not paid to an account. The shop's remaining 80% is credited to the business.

For Closed Shop restocking, an employee drops goods into the intake stash (`<id>_stock`) and closes it. Only items on the business Sales Items page move onto the shelf. Items not selected stay in the stash. A price is requested once per item type when there is no remembered price (up to `Config.pos.maxPrice`); a boss can later change shelf prices with "Set prices". On a committed purchase from a Closed Shop, the business gets 80% of the sale total.

"Take a payment" opens the itemized Appshell sale builder. Employees select from Sales Items, see their carried quantities, enter quantities and unit prices, and choose a buyer from the player list. The buyer reviews the invoice and chooses cash or card. The server verifies the selected items and removes them from the employee only when the buyer approves and pays. Till sales require the employee to be at that till; portable card machine sales require the item. See [Card machine](#card-machine).

Intake and the stock stash are job-locked regardless of `public`. Till and stash inventories are registered with `kora_inventory` using the module's coordinates and an interaction radius that covers the zone shape plus `distance`.

### Stash

Admins manage stashes from the **Stashes** page. Each stash has its own unique id, label, slot count (1-500), and max weight (1000-100000000 grams); values default from `Config.stash`. For a box, raycast its center and enter the X/Y/Z size; for a prop, enter its model and raycast to it. Creating a stash adds a separately registered inventory, and edits to its label, slots, or weight preserve its saved contents. Job-locked unless `public`. A stash id already used by another business is refused with a console warning. Contents are stored by `kora_inventory`.

### Crafting

Create and manage crafting modules from the business's **Crafters** page. Create categories such as Beer, Mixed Drinks, Prep, Salads, or Entrees; open a category to view the business's full recipe list, search by recipe or shared item name, and add or remove recipes. Then add one or more world locations to each category. When placing a location, optionally enter a prop model to raycast against that object; leave it blank for the normal raycast. The coordinates and optional model name are saved on the category location. Each location opens its category's compact recipe menu on the right side of the screen, with the output item's inventory image when available. The server checks the selected category, recipe, job access, and proximity before crafting.

### UseableItem

Binds an item to a use handler. No anchor.

| Field | Notes |
| --- | --- |
| `item` | Required, lower-cased. Bound once; if another business already holds the binding, a `register.item_handler_exists` warning is logged and the second is not bound. |
| `consume` | Items taken per use, 0 to 100, default 1. Refunded if the outcome fails. |
| `useType` | `reward` (default) or `recipe`. |
| `rewards` | For `reward`: non-empty list of `item` (or `name`), `amount` (1-1000, default 1), `chance` (relative weight, default 1). |
| `rolls` | For `reward`: picks per use, 1 to 20, default 1. Uses `Kora.rewards.generate` in weighted mode. |
| `recipe` | For `recipe`: id from the business's Recipes page or `Config.recipes`. |

Anyone with the item can use it; there is no job check.

## Card machine

The till's "Take a payment" option opens the Appshell sale builder. The portable player target is also available to employees holding `Config.payment.item`; it opens the same sale builder with the targeted customer prefilled. The seller sees items selected in Sales Items, their on-hand quantities and images. The seller selects quantities and enters each unit price, then chooses the buyer from the player list. The buyer may be the seller.

The buyer reviews the invoice and chooses cash, card, or decline. The server rechecks the catalog, seller inventory, buyer funds, and distance between different players. Cash debits the buyer's `cash` account; card debits `bank`. The seller's items are removed only when the approved payment can complete. The employee receives `floor(total * Config.payment.commission)` in their bank and the remainder is credited to the business account. If charging or business credit fails, the resource attempts to restore the items and refund the buyer.

Only items on the business's Sales Items list and currently carried by the seller can be sold. The employee enters a unit price for each selected item because Sales Items does not store retail prices. A sale is capped at `Config.payment.maxAmount`. One sale per employee and one invoice per buyer may be in flight at a time.
