---
title: "Crafting"
sidebar_position: 6
---


# Crafting

Crafting benches (world modules a staff member or the public interacts with) and useable items (consumed from the inventory, no world presence) both run through one shared transaction, `Crafting.craft`, built on the `Config.recipes` library shared with the client's menu rendering.

Namespace: `Kora.callback (server)` · Source: `server/crafting.lua`

## How it works

A bench lists recipe **ids**, not recipes: `Config.recipes[id]` is the single shared library (`shared/recipes/*.lua`), so two businesses that both grill beef reference the same definition. The client never sends a recipe — only a business id, a module index and a recipe id — and the server looks the recipe up itself; a client that lies about any of the three is rejected, not given a recipe of its own design. Server-side order in `Kora.callback.register('kora_jobcreator:server:craft', ...)` (`server/crafting.lua`): (1) the business and module must exist and the module must be a `Crafting` module; (2) unless the module is `public`, the caller must work the business's job; (3) the recipe id must be one this specific bench's `recipes` list actually offers — not merely a recipe that exists anywhere; (4) **proximity** — `State.nearModule(src, module)` must return true, or the call fails with `'You are not at the bench.'`; (5) `Crafting.craft` runs the transaction. **Proximity check (current behavior, recently fixed)**: `State.nearModule` derives its boundary from `State.moduleBoundary(module)`, which returns EVERY coordinate a module was placed at (a bench module can anchor several physical locations — several grills) plus one shared radius, and checks the caller's distance against each of those points in turn, succeeding if any one matches. This is now used uniformly for every configured crafting-bench location. Previously only the bench's first configured location was checked, which meant a bench placed at multiple spots was only usable from the first one; that has been corrected so all of a bench's locations work. **Crafting.craft** (shared by the bench callback and `UseableItem` recipe-type useables): checks `Config.skills` level requirements (only when `Config.skills.enabled`); rejects if the recipe produces nothing; checks the caller holds enough of every ingredient and has room for every output; double-checks combined capacity with `exports.kora_inventory:CanCraftItems`; then removes ingredients one at a time and finally adds every output one at a time. **Ingredient refund (recently fixed), two layers**: if removing an ingredient fails partway through, every ingredient already removed in that same craft is refunded immediately (this existed before). What was ADDED: if every ingredient was removed successfully but granting a produced item then fails (inventory full etc.), every ingredient that was removed for this craft is now refunded back to the player — `CanCraftItems` already checked combined capacity so this should not normally happen, but if it does the player is no longer left having paid ingredients for nothing. On success, `Config.skills.enabled` awards `recipe.xpGained`, and the craft is logged as a `craft` category entry. A **`UseableItem`** module (consumed from the inventory, no world anchor, `server/crafting.lua` → `Crafting.registerUseable`) either runs a `recipe` (same `Crafting.craft` path, business-logged) or rolls a `rewards` pool with `Kora.rewards.generate({ mode = 'weighted', rolls })`. The item is consumed up front and refunded if the outcome fails for any reason (recipe gone, inventory full, nothing could be carried).

## Terms used on this page

| Term | Meaning |
| --- | --- |
| State.nearModule | The server-authoritative proximity check (`server/state.lua`): true if the caller is within range of ANY coordinate the module was placed at, using a radius that already accounts for the zone shape/size plus the module's own target distance. Used uniformly for every crafting-bench module (previously only the first configured location was checked for multi-location benches). |
| CanCraftItems | A combined pre-flight capacity check against `exports.kora_inventory`, run before any ingredient is actually removed, so the vastly more common failure (not enough room, not enough ingredients) never has to be unwound. |

## Config.recipes entry fields (shared/recipes/*.lua)

Pass an options table as the final argument to a play function. Omit the table or any field to use its default. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `label / icon` | string | Shown in the bench menu; icon is an optional lucide icon name. |
| `time / progressLabel / completeLabel` | integer / string | `time` (ms) drives the client progress bar; omit for an instant craft. `completeLabel` defaults to an auto-generated message. |
| `anim` | table | `{ dict, clip, flag }` played for the progress bar's duration. |
| `ingredients / give` | table[] | `{ item, amount }` consumed / produced. Enforced and applied server-side regardless of what the client's progress bar showed. |
| `levelRequired / xpGained?` | table[] | `{ skill, level }` / `{ skill, xp }` — only enforced/awarded when `Config.skills.enabled` is true. |

## Functions

1 server callback. `Crafting.registerUseable` (useable-item binding) and `Crafting.craft`/`Crafting.entries` (the transaction itself) are internal Lua functions on `KoraJobCreator.crafting`, not registered callbacks or exports — another resource cannot call them directly.

### `Kora.callback.trigger('kora_jobcreator:server:craft', businessId, moduleIndex, recipeId)`

Runs one crafting-bench recipe for the caller. See "The crafting flow, precisely" in How to use for the full ordered behavior, including the proximity check and ingredient-refund behavior.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |
| `moduleIndex` | integer | The Crafting module's 1-based position in the business. |
| `recipeId` | string | Must be one of the ids in that specific module's `recipes` list. |

**Returns**

- **ok, message** — true and a success message (`recipe.completeLabel`, or an auto-generated "You made &lt;items>." message) on success.
- **err** — `'Unknown business.'`, `'Unknown crafting bench.'`, `'You do not work here.'` (non-public bench, wrong job), `'That is not made here.'` (recipe id not on this bench), `'Unknown recipe.'`, `'You are not at the bench.'` (proximity check failed), `'You need <skill> level <n>.'`, `'That recipe produces nothing.'`, `'You are missing ingredients.'`, or `'You do not have room for that.'`.

**Example**

```lua
local ok, message = Kora.callback.trigger('kora_jobcreator:server:craft', 'burgershot', 5, 'bs_burger')
```

**Representative console output**

```text
ok = true, message = 'One Bleeder, ready to go.' — one beef, one sliced onion and one bun are consumed and one burger is granted in the same call. Rate-limited to 20 per 10s.
```

## Limits and related APIs

A recipe or bench is static server config, not database-backed — adding one requires a resource restart (new recipe files or an edited `Config.recipes`/module list), unlike a business definition itself. Skill gating is entirely inert unless `Config.skills.enabled = true` and the integration functions in `config.lua` are backed by a real skills system.

## Related guides

- [Point of sale & stashes](./pos-stash.md)
- [Business registry & admin console](./registry-admin.md)
