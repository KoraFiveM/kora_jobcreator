---
title: "Cross-resource exports"
sidebar_position: 7
---


# Cross-resource exports

## Client

Two client exports: the local replicated-definitions mirror, and a way to open the management console from another client script.

Namespace: `exports.kora_jobcreator` · Source: `client/main.lua`

### Functions

2 client exports.

#### `exports.kora_jobcreator:getBusinesses()`

The client's locally replicated definitions — exactly what this client has synced, keyed by business id.

**Parameters**



**Returns**

- **table&lt;string, table>** — businessId -> definition as replicated (webhook URLs omitted).

**Example**

```lua
local businesses = exports.kora_jobcreator:getBusinesses()
```

**Representative console output**

```text
Reflects only what has been synced to THIS client so far; see `kora_jobcreator:server:hydrate` for the server's authoritative snapshot.
```

#### `exports.kora_jobcreator:openBusinessMenu()`

Opens the same console `/jobcreator` opens.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
exports.kora_jobcreator:openBusinessMenu()
```

**Representative console output**

```text
Equivalent to running `/jobcreator` from another client script.
```

## Server

Read access to the business registry and staff counts for other server resources, plus a way to write into this resource's own activity log/webhook feed without duplicating that plumbing.

Namespace: `exports.kora_jobcreator` · Source: `server/admin.lua`

### Functions

5 server exports.

#### `exports.kora_jobcreator:getBusinesses()`

Every business definition, including module webhooks (`State.snapshot(true)`). Server-trusted callers only — this is the PRIVATE snapshot.

**Parameters**



**Returns**

- **table[]** — array of `{ id, label, job, modules, rev }`, sorted by id.

**Example**

```lua
local businesses = exports.kora_jobcreator:getBusinesses()
```

**Representative console output**

```text
Includes webhook URLs; never forward this to a client.
```

#### `exports.kora_jobcreator:getBusiness(id)`

One business by id, as a detached copy (safe to mutate without affecting the live registry).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string |  |

**Returns**

- **business** — table, or `nil` if unknown.

**Example**

```lua
local business = exports.kora_jobcreator:getBusiness('burgershot')
```

**Representative console output**

```text
nil for an unknown or deleted id.
```

#### `exports.kora_jobcreator:getBusinessesByJob(job)`

Every business id assigned to a given kora_core job.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `job` | string |  |

**Returns**

- **ids** — sorted array of business id strings (possibly empty).

**Example**

```lua
local ids = exports.kora_jobcreator:getBusinessesByJob('burgershot')
```

**Representative console output**

```text
{ 'burgershot' }
```

#### `exports.kora_jobcreator:getStaffCounts()`

Current staffed-presence counts for every business with at least one person present (pruned against live job/duty/proximity first).

**Parameters**



**Returns**

- **table&lt;string, integer>** — businessId -> count.

**Example**

```lua
local counts = exports.kora_jobcreator:getStaffCounts()
```

**Representative console output**

```text
{ burgershot = 2 }
```

#### `exports.kora_jobcreator:recordBusinessLog(businessId, category, message, amount?)`

Lets another resource append a row to a business's activity log/webhook feed as if it were one of this resource's own categories.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `businessId` | string |  |
| `category` | string | Free-form, truncated to 32 characters; `admin` is used when omitted or not a string. |
| `message` | string |  |
| `amount?` | number |  |

**Returns**

- **ok** — true on success.
- **err** — `'unknown business'` for an unrecognised id.

**Example**

```lua
exports.kora_jobcreator:recordBusinessLog('burgershot', 'admin', 'Reassigned a till from a linked resource.')
```

**Representative console output**

```text
Writes the row and, if a webhook is configured for this business's job (or `Config.webhooks.default`, server-only config in `server/config.lua`), posts a Discord embed.
```

### Quick reference

#### Server

| Export | Returns |
| --- | --- |
| `getBusinesses()` | Array of every business, sorted by id, with each module including `webhook` fields. Fields per business: `id`, `label`, `job`, `modules`, `rev`. |
| `getBusiness(id)` | A deep copy of one business (also includes `rev` and a `rejected` list of modules that failed validation), or `nil`. |
| `getBusinessesByJob(job)` | Sorted array of business ids whose `job` equals the argument. |
| `getStaffCounts()` | Table of business id to number of verified on-duty staff inside. |
| `recordBusinessLog(businessId, category, message, amount)` | `true`, or `false` and `'unknown business'`. `category` is truncated to 32 characters (non-strings become `admin`); `amount` is optional. Writes the log row, the `Kora.logging` event and any webhooks. |

```lua
local ids = exports.kora_jobcreator:getBusinessesByJob('burgershot')
exports.kora_jobcreator:recordBusinessLog('burgershot', 'admin', 'Audit note', nil)
```

#### Client

| Export | Returns |
| --- | --- |
| `getBusinesses()` | Table keyed by business id of the replicated definitions (module `webhook` removed). |
| `openBusinessMenu()` | Opens the console, as `/jobcreator` does. |

### Limits and related APIs

`getBusinesses` (server) includes webhook URLs and must never be relayed to a client as-is; use the client export or the replicated `kora_jobcreator:client:sync` data for anything client-facing.
