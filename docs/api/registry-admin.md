---
title: "Business registry & admin console"
sidebar_position: 2
---


# Business registry & admin console

Everything an administrator or job boss does from the `/jobcreator` NUI console: create, rename/reassign and delete businesses, add/edit/remove modules, and read a business's activity log and account balance. Every mutation is a whole-business write — the caller's change is applied to a detached copy of the module list (`json.decode(json.encode(business.modules))`), the copy is validated by `S.normaliseBusiness`/`S.normaliseModule`, and only a successful validate-and-persist moves the in-memory registry and re-broadcasts. A rejected edit therefore never leaves the database or the live server half-applied.

Namespace: `Kora.callback (server)` · Source: `server/admin.lua, server/state.lua`

## How it works

`State.persist(raw)` is the single write path for every one of these: validate → `INSERT ... ON DUPLICATE KEY UPDATE` into `kora_jobcreator` → update the in-memory mirror and stamp a fresh `rev` → `State.broadcast()` to every client. `authorise(src, businessId, requireAdmin)` is the shared gate: `requireAdmin = true` for every true mutation (create/edit/delete/module/saveModule/removeModule), `false` for read-only access (logs/balance), which also accepts a job boss.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| rev | An FNV-1a fingerprint of `{ label, job, modules }`, recomputed on every persist. A client only rebuilds a business whose `rev` changed since its last sync. |
| Detached copy | `copyModules(business)` round-trips the module list through `json.encode`/`json.decode` so an edit never mutates the live, already-registered business table in place before validation passes. |

## Functions

10 server callbacks, registered with `Kora.callback.register('kora_jobcreator:server:<name>', handler, { rateLimit = ... })`.

### `Kora.callback.trigger('kora_jobcreator:server:hydrate')`

The client's one full-snapshot request on connect/character-load/local-restart: every business, current staff-presence counts, and whether the caller is an admin.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |

**Returns**

- **`{ businesses: table[], staff: table<string,integer>, admin: boolean, ready: boolean }`** — `ready` is `false` while `State.load()` is still running at boot; the client keeps retrying every 2s until it is `true`.

**Example**

```lua
local data = Kora.callback.trigger('kora_jobcreator:server:hydrate')
if type(data) == 'table' and data.ready then
    print(#data.businesses, 'businesses', data.admin and '(admin)' or '')
end
```

**Representative console output**

```text
Called once on resource start by client/main.lua; rate-limited to 5 per 10s.
```

### `Kora.callback.trigger('kora_jobcreator:server:jobs')`

The job picker list an admin chooses from when creating a business. Admin-only.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |

**Returns**

- **jobs** — array of `{ value = jobName, label }`, sorted by label, excluding `unemployed`.
- **err** — `'You cannot edit businesses.'` for a non-admin (jobs is then `nil`).

**Example**

```lua
local jobs, err = Kora.callback.trigger('kora_jobcreator:server:jobs')
```

**Representative console output**

```text
Backs the "Create business" job `select` field.
```

### `Kora.callback.trigger('kora_jobcreator:server:createBusiness', payload)`

Creates a new business with zero modules. Admin-only.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `payload` | table | `{ label, job }`. The id is slugged from `payload.id or payload.label`. |

**Returns**

- **businessId** — the new business's id on success.
- **err** — `'Businesses are still loading.'`, `'You cannot create businesses.'`, `'Invalid business.'`, `'That name cannot be used as an id.'`, `'A business with that id already exists.'`, `'That job does not exist.'`, or a persistence error.

**Example**

```lua
local id, err = Kora.callback.trigger('kora_jobcreator:server:createBusiness', { label = 'Pizza This', job = 'pizzathis' })
```

**Representative console output**

```text
id = 'pizza_this'. Logged as an `admin` activity row. Rate-limited to 5 per 30s.
```

### `Kora.callback.trigger('kora_jobcreator:server:editBusiness', businessId, payload)`

Renames a business and/or reassigns its job. Never changes its id: a business's id is its primary key and is referenced by log rows and till ids, so an id change is a delete-and-rebuild, not an edit. Admin-only.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |
| `payload` | table | `{ label?, job? }` — either or both; omitted fields keep their current value. |

**Returns**

- **ok** — true on success.
- **err** — authorisation error, `'Invalid business.'`, `'That job does not exist.'`, or a persistence error.

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:editBusiness', 'burgershot', { label = 'Burger Shot (Downtown)' })
```

**Representative console output**

```text
Modules are untouched; only label/job change. Rate-limited to 10 per 30s.
```

### `Kora.callback.trigger('kora_jobcreator:server:deleteBusiness', businessId)`

Deletes a business and writes a deletion marker so a seed with the same id is never resurrected on restart. Stashes and till stock already in kora_inventory are left untouched (only the business row and its registrations are removed). Admin-only.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |

**Returns**

- **ok** — true on success.
- **err** — authorisation error or `'Could not delete the business.'`.

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:deleteBusiness', 'burgershot')
```

**Representative console output**

```text
The deletion is logged against the business that no longer exists, on purpose — "who deleted this" is exactly what you want afterwards. Rate-limited to 5 per 30s.
```

### `Kora.callback.trigger('kora_jobcreator:server:module', businessId, index)`

Fetches one module's FULL data (including its webhook, which public snapshots omit) for the in-game "Edit data" JSON editor. Admin-only.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |
| `index` | integer | 1-based position in the business's module list. |

**Returns**

- **module** — a detached copy of the module table, or `nil`.
- **err** — authorisation error or `'That module no longer exists.'`.

**Example**

```lua
local module = Kora.callback.trigger('kora_jobcreator:server:module', 'burgershot', 3)
```

**Representative console output**

```text
Rate-limited to 10 per 10s.
```

### `Kora.callback.trigger('kora_jobcreator:server:saveModule', businessId, index, payload)`

Appends a module (`index` nil) or replaces one in place. Re-validates the WHOLE business by applying the change to a detached copy of the module list, then persisting that copy as one row — a rejected module leaves the business exactly as it was. Admin-only.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |
| `index?` | integer | Omit to append; otherwise the 1-based position to replace. |
| `payload` | table | Raw module fields; validated by `S.normaliseModule` (see the schema concepts in How to use). |

**Returns**

- **ok, position** — `true` and the module's 1-based position on success.
- **err** — authorisation error, `'That module no longer exists.'` (replacing a stale index), or the schema's own rejection reason (for example `'this module needs coords'`).

**Example**

```lua
local ok, posOrErr = Kora.callback.trigger('kora_jobcreator:server:saveModule', 'burgershot', nil, {
    moduleType = 'Stash', label = 'Dry Storage', id = 'burgershot_dry', slots = 40, weight = 200000,
    zoneType = 'sphere', coords = { x = -1196.0, y = -897.0, z = 13.9 }, radius = 1.5,
})
```

**Representative console output**

```text
ok = true, posOrErr = 7 (appended as the 7th module). Logged as `admin`; the world rebuilds on the next sync. Rate-limited to 20 per 30s.
```

### `Kora.callback.trigger('kora_jobcreator:server:removeModule', businessId, index)`

Removes one module from a business. Admin-only.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |
| `index` | integer | 1-based position. |

**Returns**

- **ok** — true on success.
- **err** — authorisation error or `'That module no longer exists.'`.

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:removeModule', 'burgershot', 7)
```

**Representative console output**

```text
Rate-limited to 20 per 30s.
```

### `Kora.callback.trigger('kora_jobcreator:server:logs', businessId, limit?)`

Recent activity rows for a business's console. Open to admins AND bosses of that business (read-only, `requireAdmin = false`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |
| `limit?` | integer | Default 25, clamped 1–100. |

**Returns**

- **rows** — array of `{ category, message, amount, created_at }`, newest first.
- **err** — authorisation error (not admin and not a boss of this business).

**Example**

```lua
local rows = Kora.callback.trigger('kora_jobcreator:server:logs', 'burgershot', 50)
```

**Representative console output**

```text
Rate-limited to 10 per 10s.
```

### `Kora.callback.trigger('kora_jobcreator:server:balance', businessId)`

The business's account balance via `exports.kora_bossmenu:getBusinessBalance(job)`. Open to admins and bosses of that business.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |

**Returns**

- **balance** — a number on success.
- **err** — authorisation error, or `'No business account resource is running.'` when kora_bossmenu is not started.

**Example**

```lua
local balance, err = Kora.callback.trigger('kora_jobcreator:server:balance', 'burgershot')
```

**Representative console output**

```text
Rate-limited to 10 per 10s.
```

## Limits and related APIs

No pagination: `logs` is capped at 100 rows per call and the client paginates business/module lists itself. `editBusiness` cannot rename a business's id — delete and recreate for that. Admin permission and boss-grade are both re-read from `kora_core` on every call; nothing here trusts a cached client-side role.

## Related guides

- [Staff presence & duty](./staff-duty.md)
- [Point of sale & stashes](./pos-stash.md)
- [Cross-resource exports](./cross-resource-exports.md)
