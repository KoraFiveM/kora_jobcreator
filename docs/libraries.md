---
title: Libraries and seeds
sidebar_position: 8
---

# Libraries and seeds

Three shared Lua libraries are loaded from `shared/` (see `fxmanifest.lua`). Add a new file in the matching folder to extend them; the files are loaded by glob.

## Recipes

`shared/recipes/*.lua` fills `Config.recipes`, keyed by id. A Crafting module or a recipe-type UseableItem refers to a recipe by id.

```lua
Config.recipes['bs_burger'] = {
    label = 'Bleeder burger',
    icon = 'Hamburger',
    time = 6000,
    progressLabel = 'Building a burger',
    completeLabel = 'One Bleeder, ready to go.',
    anim = { dict = 'dict', clip = 'clip', flag = 1 },
    ingredients = { { item = 'beef', amount = 1 } },
    give = { { item = 'burger', amount = 1 } },
    levelRequired = { { skill = 'cooking', level = 2 } },
    xpGained = { { skill = 'cooking', xp = 10 } },
}
```

| Field | Notes |
| --- | --- |
| `label` | Shown in the bench menu. |
| `icon` | Optional menu icon. |
| `time` | Progress bar duration in ms. Omit for an instant craft. The bar is cancelable and blocks movement, combat and vehicles. |
| `progressLabel`, `completeLabel` | Bar text and success message. |
| `anim` | Animation played during the bar. |
| `ingredients` | List of `item` and `amount`; an entry may also use `name` and `count`, plus `info` or `metadata`. |
| `give` | Same shape. A recipe with no `give` entries fails with "That recipe produces nothing." |
| `levelRequired`, `xpGained` | Only used when `Config.skills.enabled`. |

The server checks ingredients, carry room (`canCarry` and `CanCraftItems`), removes ingredients and adds results. If removal or delivery fails part-way, already-taken ingredients are returned.

The shipped file defines `bs_beef`, `bs_slicedonion`, `bs_slicedpotato`, `bs_burger` and `bs_fries`.

## Shop-item lists

`shared/shopitems/*.lua` fills `Config.shopItems`, keyed by list name. A POS module names lists in `items`.

```lua
Config.shopItems['burgershot'] = {
    { item = 'burger', price = 12 },
    { item = 'sprunk' },
}
```

An entry with `price` is fixed (it cannot be repriced, and the employee is not asked). An entry without `price` is allowed and priced by the employee on first stocking; the price is remembered. If a list is referenced, only its items may be stocked.

## Seeds

`shared/businesses/*.lua` appends business definitions to `Config.seeds`. A seed is an ordinary business definition (`id`, `label`, `job`, `modules`) plus an optional seed-only `jobDefinition`.

- A business is inserted only if no business with that id exists and no deletion marker exists in `kora_jobcreator_deleted`. Deleting or editing it in-game always wins; an admin can still recreate the same id by hand.
- A `jobDefinition` is registered with `kora_core` (`registerShared('jobs', ...)`) on every boot when no job of that name exists yet, because the job registry is rebuilt in memory each start. A server that already defines the job keeps its own.

The shipped seed is `burgershot`: a job with grades Trainee, Cook, Shift Lead and Manager (boss); and modules Zone (sphere, radius 22), Blip, POS `burgershot_till` (commission 5, tax 10, hideWhenStaffed, panicButton), Stash `burgershot_fridge`, Crafting "Grill" and BossMenu "Manager Desk". To avoid it, delete `shared/businesses/burgershot.lua`.
