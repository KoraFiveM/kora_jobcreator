---
title: "Point of sale & stashes"
sidebar_position: 4
---


# Point of sale & stashes

Policy around a till: which items it accepts, what they cost, the restock-to-shelf pipeline, the customer purchase payout (tax, commission, business credit), the portable panic alarm, and plain employee/public stashes. Stock itself is NOT stored by this resource — kora_inventory already owns and durably persists shop/stash inventories, so duplicating that here would create two sources of truth for the same shelf.

Namespace: `Kora.callback (server)` · Source: `server/pos.lua, server/register.lua`

## How it works

Sales are credited from kora_inventory's post-commit `kora_inventory:server:audit` purchase event (never a pre-commit hook, which could pay out for a sale that still fails afterwards). Restocking prices items once per distinct name at intake time (before any yield), then moves everything from the intake stash to the shelf in one non-yielding pass so an item can never be left simultaneously in both places. A deliberate design detail: `module.commission` is paid only to the citizenid still attached as a slot's stocker at sale time — that attribution is server-only inventory metadata, never client-trusted.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| fixedPrices | Computed once per till from its `Config.shopItems` list(s): an item with a configured `price` cannot be repriced by staff or boss; one with no price is employee-priced on first restock and then remembered. |
| intake | The pipeline that runs when an employee closes a till's stock stash: price unpriced items (may prompt the employee), then move everything the till accepts onto the shelf, merging into a matching stack when possible. |

## Config.pos (config.lua)

Pass an options table as the final argument to a play function. Omit the table or any field to use its default.

| Option | Type | Description |
| --- | --- | --- |
| `shopSlots / shopWeight` | integer | Default slots/weight for a till's customer-facing shop (50 / 1,000,000 g); a POS module may override `shopSlots`. |
| `stockSlots / stockWeight` | integer | Default slots/weight for the intake stash. |
| `currency` | string | `cash` or `bank` — which account customers pay from by default; a POS module may override it per till. |
| `maxPrice` | integer | Hard cap (default 1,000,000) on any price an employee may set, so a typo cannot create a multi-million dollar till entry. |

## Functions

6 server callbacks.

### `Kora.callback.trigger('kora_jobcreator:server:openShop', shopId)`

Opens a till's customer-facing shop inventory. The access rule (job lock unless `public`, and `hideWhenStaffed`) is enforced by kora_inventory's own `access` callback supplied at registration, not re-checked here.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `shopId` | string | The POS module's `id`. |

**Returns**

- **ok** — true, or false with a reason from kora_inventory (for example the till being closed for this player).

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:openShop', 'burgershot_till')
```

**Representative console output**

```text
Rate-limited to 10 per 10s.
```

### `Kora.callback.trigger('kora_jobcreator:server:openStock', shopId)`

Opens the employee-facing intake stash goods are dropped into before they reach the shelf. Requires the caller to work the business and be near the till (`State.employeeAt`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `shopId` | string |  |

**Returns**

- **ok** — true, or false with an access-denied reason.

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:openStock', 'burgershot_till')
```

**Representative console output**

```text
Closing this stash triggers `Pos.intake`, which prices and moves everything onto the shelf. Rate-limited to 10 per 10s.
```

### `Kora.callback.trigger('kora_jobcreator:server:tillPrices', shopId)`

The current shelf as a boss-facing price list, for the in-game price editor. Boss/admin only (`tillContext(..., requireBoss = true)`), and requires standing near the till.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `shopId` | string |  |

**Returns**

- **till** — `{ shop, label, max, items: [{ slot, name, label, amount, price, fixed }] }`.
- **err** — `'Only a boss can do that.'`, `'You are too far away.'`, or `'Unknown till.'`.

**Example**

```lua
local till = Kora.callback.trigger('kora_jobcreator:server:tillPrices', 'burgershot_till')
```

**Representative console output**

```text
Rate-limited to 10 per 10s.
```

### `Kora.callback.trigger('kora_jobcreator:server:setTillPrice', shopId, slot, price)`

Repriced one shelf slot. Rejects a fixed-price item (one covered by the till's configured shop-item list with a `price`) outright. Boss/admin only, near the till.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `shopId` | string |  |
| `slot` | integer |  |
| `price` | integer |  |

**Returns**

- **ok** — true on success.
- **err** — access error, `'That price is out of range.'` (outside 0–`Config.pos.maxPrice`), `'That slot is empty.'`, or `'That item has a fixed price.'`.

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:setTillPrice', 'burgershot_till', 3, 15)
```

**Representative console output**

```text
Remembers the price for every future restock of that item at this till, and logs an `admin` row. Rate-limited to 20 per 10s.
```

### `Kora.callback.trigger('kora_jobcreator:server:panic', businessId, shopId)`

The silent alarm on a till configured with `panicButton = true`. Requires the caller to be an on-duty employee of the business (`State.employeeAt(src, business, record, true)`) and `kora_dispatch` to be running.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |
| `shopId` | string |  |

**Returns**

- **ok, recipients** — true and whatever `exports.kora_dispatch:createCall` returns for who was dispatched.
- **err** — `'This till has no panic button.'`, an `employeeAt` rejection, or `'No dispatch service is available.'` (kora_dispatch not started) — unclear: the exact shape of `recipients` depends on kora_dispatch and was not inspected here.

**Example**

```lua
local ok, recipients = Kora.callback.trigger('kora_jobcreator:server:panic', 'burgershot', 'burgershot_till')
```

**Representative console output**

```text
Anchors the call at whichever of the till's placed coordinates is closest to the caller. Logged as a `panic` activity row. Rate-limited to 3 per 30s.
```

### `Kora.callback.trigger('kora_jobcreator:server:openStash', stashId)`

Opens a plain `Stash` module (not a till's intake stash). kora_inventory already gates the stash on its own `groups`; this callback exists so a player who cannot open it is TOLD why, rather than watching nothing happen.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `stashId` | string | The Stash module's `id`. |

**Returns**

- **ok** — true, or false with a reason.
- **err** — `'Unknown stash.'`, `'Unknown business.'`, or `'You do not work here.'` for a non-`public` stash.

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:openStash', 'burgershot_fridge')
```

**Representative console output**

```text
Rate-limited to 10 per 10s.
```

## Limits and related APIs

A till id shared by two different businesses keeps whichever business registered it first and logs a console warning; conflicting commission/tax on a shared id is also only a console warning, not a hard error. Panic requires `kora_dispatch`; commission requires `kora_bossmenu`.

## Related guides

- [Business registry & admin console](./registry-admin.md)
- [Staff presence & duty](./staff-duty.md)
- [Crafting](./crafting.md)
