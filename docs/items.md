---
title: Items
sidebar_position: 12
---

# Items

The resource defines no items. Item names must exist in your `kora_core` and `kora_inventory` item definitions.

| Item | Where it comes from | Used for |
| --- | --- | --- |
| `cardmachine` | `Config.payment.item` | Shows the "Take a payment" option on players. |
| Any `item` of a UseableItem module | The module | Registered as useable through `kora_inventory:createUseable`. |
| Recipe ingredients and results | `Config.recipes` | Removed and added by crafting. |
| Till and reward items | `Config.shopItems`, module `rewards` | Stocked, sold or awarded. |

The Burger Shot seed assumes these exist: `burgermeat`, `beef`, `onion`, `slicedonion`, `potato`, `slicedpotato`, `bun`, `burger`, `fries`, `water_bottle`, `sprunk`. See the files in `shared/recipes/` and `shared/shopitems/` for exact usage. A recipe item that does not exist makes crafting fail at the carry or ingredient checks.
