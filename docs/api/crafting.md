---
title: "Crafting"
sidebar_position: 6
---


# Crafting

Crafting benches (world modules a staff member or the public interacts with) and useable items (consumed from the inventory, no world presence) both run through one shared transaction, `Crafting.craft`, built on the `Config.recipes` library shared with the client's menu rendering.

Namespace: `Kora.callback (server)` · Source: `server/crafting.lua`

## How it works

A crafter holds recipe **ids**, not recipes: either one list on a single anchored bench, or one list per category on a crafter with categories. Each id resolves to the business's own SQL recipe first (see [Recipes and stores](./job-recipes.md)), then to the shared `Config.recipes` library. The client never sends a recipe, only a business id, a module index, a category id and a recipe id; the server looks the recipe up itself.

Server-side order in `kora_jobcreator:server:craft` (`server/crafting.lua`):

1. The business and module must exist and the module must be a `Crafting` module.
2. The caller must work the business's job. `public` does not open a crafter.
3. The category must exist on that module (`default` names a single bench).
4. The recipe id must be in that category's list, not merely a recipe that exists anywhere.
5. **Proximity**: `State.nearModule` must pass against every location of the category (or every anchor point of a single bench), or the call fails with `'You are not at the bench.'`.
6. `Crafting.craft` runs the transaction.

**Crafting.craft** (shared by the bench callback and `UseableItem` recipe-type useables) checks `levelRequired` (only when `Config.skills.enabled`), rejects a recipe that produces nothing, checks ingredients and room for every output, double-checks combined capacity with `exports.kora_inventory:CanCraftItems`, then removes ingredients one at a time and adds every output one at a time. If an ingredient removal fails partway, the ingredients already removed are refunded; if granting an output fails, every removed ingredient is refunded. On success `xpGained` is awarded (when skills are enabled) and the craft is logged as `craft`.

A **`UseableItem`** module either runs a `recipe` (same `Crafting.craft` path, resolved against that business's recipes first) or rolls a `rewards` pool with `Kora.rewards.generate({ mode = 'weighted', rolls })`. The item is consumed up front and refunded if the outcome fails for any reason.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| State.nearModule | The server-authoritative proximity check (`server/state.lua`): true if the caller is within range of ANY of the given coordinates. For a single bench the radius covers the zone shape plus the module's `distance`; for a category location it is twice the module's `distance` (the location target is a sphere of that radius). |
| CanCraftItems | A combined pre-flight capacity check against `exports.kora_inventory`, run before any ingredient is actually removed, so the vastly more common failure (not enough room, not enough ingredients) never has to be unwound. |

## Recipe fields (Config.recipes and business recipes)

Pass an options table as the final argument to a play function. Omit the table or any field to use its default. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `label` | string | Shown in the crafting menu. |
| `time / progressLabel / completeLabel` | integer / string | `time` (ms) drives the client progress bar; omit for an instant craft. `completeLabel` defaults to an auto-generated message. |
| `anim` | table | `{ dict, clip, flag }` played for the progress bar's duration. |
| `ingredients / give` | table[] | `{ item, amount }` consumed / produced. Enforced and applied server-side regardless of what the client's progress bar showed. |
| `levelRequired / xpGained?` | table[] | `{ skill, level }` / `{ skill, xp }` — only enforced/awarded when `Config.skills.enabled` is true. |

## Functions

2 server callbacks. `Crafting.registerUseable`, `Crafting.craft` and `Crafting.entries` are internal Lua functions on `KoraJobCreator.crafting`, not callbacks or exports.

### `Kora.callback.trigger('kora_jobcreator:server:craft', businessId, moduleIndex, categoryId, recipeId)`

Runs one recipe for the caller. The older three-argument form `(businessId, moduleIndex, recipeId)` still crafts at a single bench.

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id, supplied automatically to the handler. |
| `businessId` | string | |
| `moduleIndex` | integer | The Crafting module's 1-based position in the business. |
| `categoryId` | string | A category id on that crafter, or `default` for a single bench. |
| `recipeId` | string | Must be in that category's (or bench's) recipe list. |

**Returns** `true, message` on success (`recipe.completeLabel`, or "You made ..."), otherwise `false` and one of: `'Unknown business.'`, `'Unknown crafting bench.'`, `'You do not work here.'`, `'Unknown crafting station.'`, `'That is not made here.'`, `'Unknown recipe.'`, `'You are not at the bench.'`, `'You need <skill> level <n>.'`, `'That recipe produces nothing.'`, `'You are missing ingredients.'`, `'You do not have room for that.'`. Rate-limited to 20 per 10 s.

```lua
local ok, message = Kora.callback.trigger('kora_jobcreator:server:craft', 'diner', 6, 'prep', 'salad')
```

### `Kora.callback.trigger('kora_jobcreator:server:benchRecipes', businessId, moduleIndex, categoryId)`

Returns the recipes one category (or a single bench, `default`) offers, in order, each with its `id` and an `output` entry (its first `give` item) for the menu image. Requires the caller's job to match the business. Rate-limited to 20 per 10 s.

## Limits and related APIs

Shared `Config.recipes` are static files and need a resource restart to change. Business recipes and crafters are edited in-game and take effect immediately. Skill gating is entirely inert unless `Config.skills.enabled = true` and the integration functions in `config.lua` are backed by a real skills system.

## Related guides

- [Point of sale & stashes](./pos-stash.md)
- [Business registry & admin console](./registry-admin.md)
