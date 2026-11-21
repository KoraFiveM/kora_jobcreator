---
title: "Recipes and stores"
sidebar_position: 7
---

# Recipes and stores

Business recipes are created on a business's **Recipes** page and stored in `kora_jobcreator_business_recipes`, private to that business. Employee stores live on the business's `SalesItems` module and are edited on the **Stores** page. Every callback below carries a rate limit.

Namespace: `Kora.callback` · Source: `server/recipes.lua`, `server/stores.lua`

## Recipes

A recipe is `{ label, ingredients, give, time?, progressLabel?, completeLabel?, anim?, levelRequired?, xpGained? }`, validated by `S.normaliseRecipe` (`shared/schema.lua`) before it is written and again when it is loaded.

| Field | Rules |
| --- | --- |
| `label` | Required, up to 64 characters. The id is slugged from it on creation and stays fixed. |
| `ingredients` | Up to 16 `{ item, amount }`; may be empty. |
| `give` | 1 to 16 `{ item, amount }`. |
| `amount` | 1 to 1000, default 1. Item names are lower-cased. |
| `time` | Milliseconds, 0 to 600000. |

Every ingredient and output must be a registered item. Within a business, its own recipe shadows a shared `Config.recipes` entry with the same id.

### `kora_jobcreator:server:recipes`

`(businessId)` · admin · 10 per 10 s. Returns `{ business = recipe[], shared = { id, label }[] }`. Each business recipe carries its `id` and `usages` (where it is referenced).

### `kora_jobcreator:server:saveRecipe`

`(businessId, id, recipe)` · admin · 20 per 30 s. `id = nil` creates a recipe and returns its new id; an existing id updates it. Returns `nil, error` for an invalid recipe, an unknown item, or an unknown id.

### `kora_jobcreator:server:deleteRecipe`

`(businessId, id)` · admin · 10 per 30 s. Refused while a crafter category, single bench or useable item of that business still references the recipe; the error names them.

### `kora_jobcreator:server:benchRecipes`

See [Crafting](./crafting.md).

## Employee stores

### `kora_jobcreator:server:storeCatalog`

`(businessId, storeId)` · 10 per 10 s. For an employee of the business near one of the store's locations, returns `{ id, label, payFrom, items = { name, label, price }[] }`.

### `kora_jobcreator:server:purchaseStoreItem`

`(businessId, storeId, itemName, amount)` · 10 per 10 s. Checks job, proximity, that the item is in that store, that `amount` is a whole number from 1 to `Config.stores.maxQuantity`, and carrying capacity. The price always comes from the saved store.

- `payFrom = 'player'`: one `kora_core` transaction removes `price * amount` from `Config.stores.account` and adds the items.
- `payFrom = 'business'`: the business account is debited through `kora_bossmenu`, then the items are added; if adding fails, the business is refunded.

Returns `true, message` or `false, error`, and logs the pickup under `stock`. One pickup per player may be in flight.

```lua
local ok, message = Kora.callback.trigger('kora_jobcreator:server:purchaseStoreItem', 'diner', 'produce', 'lettuce', 5)
```

## Related guides

- [Modules](../modules.md)
- [Crafting](./crafting.md)
- [Database](../database.md)
