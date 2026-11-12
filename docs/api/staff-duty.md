---
title: "Staff presence & duty"
sidebar_position: 3
---


# Staff presence & duty

Who is standing inside which business right now (for the staffed-till hide rule and the management console's "Staff present" stat) and the automatic on/off-duty toggle as a player crosses a business perimeter.

Namespace: `Kora.callback (server)` · Source: `server/staff.lua`

## How it works

Presence is a plain `businessId -> set<src>` table, pruned (not just appended to) on every read and on a 5-second sweep, and re-verified against the player's CURRENT job, duty state and live ped position every time — so a forged or stale claim is dropped on the next prune rather than trusted until an explicit leave arrives. It is also cleared on `playerDropped`, `QBCore:Server:OnPlayerUnload`, `QBCore:Server:OnJobUpdate` and going off duty. Presence counts are pushed to every client as `kora_jobcreator:client:staff` whenever they change.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| employeeAt | Shared gate in `server/state.lua`: correct job (any grade) and, when `requireDuty` is set, on duty, and within range of either a given module or any of the business's Zone modules. |

## Functions

3 server callbacks.

### `Kora.callback.trigger('kora_jobcreator:server:enter', businessId)`

Claims the caller as present/working inside a business, used for the staffed-till count and panic-button eligibility. The server independently verifies job, duty and live proximity before accepting it — a client reporting the transition is a trigger, not a trust.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |

**Returns**

- **ok** — true when accepted (business exists and `State.employeeAt(src, business, nil, true)` — correct job, on duty, near a Zone module).

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:enter', 'burgershot')
```

**Representative console output**

```text
Adds the caller to the business's present-staff set and republishes staff counts to every client. Rate-limited to 20 per 10s.
```

### `Kora.callback.trigger('kora_jobcreator:server:leave', businessId)`

Clears the caller's presence claim for a business.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |

**Returns**

- **ok** — true when the caller was present and is now removed.

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:leave', 'burgershot')
```

**Representative console output**

```text
Rate-limited to 20 per 10s.
```

### `Kora.callback.trigger('kora_jobcreator:server:setDuty', businessId, onDuty)`

Automatic clock-on/off as a staff member crosses a `Zone` module's perimeter (only when `Config.duty.enabled` and the module's own `controlDuty` is not `false`). The client decides WHEN to ask (it owns the zone-enter/exit events); the server decides WHETHER, re-reading the caller's real job and proximity rather than trusting the business id to imply either.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `businessId` | string |  |
| `onDuty` | boolean |  |

**Returns**

- **ok** — true on success.
- **err** — `'Automatic duty is disabled.'`, `'Unknown business.'`, `'Automatic duty is not available here.'` (not near a duty-controlling Zone), an `employeeAt` rejection, or `false` with no message when duty is already in that state.

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:setDuty', 'burgershot', true)
```

**Representative console output**

```text
Calls `exports.kora_core:setJobDuty`, notifies the player, and (going off duty) clears every presence claim they held. Rate-limited to 10 per 10s.
```

## Limits and related APIs

Presence is in-memory only and not persisted; a full server restart clears it (clients re-enter their zones and re-claim presence on the next load). `setDuty` only fires through a `Zone` module whose own `controlDuty` is not explicitly `false`.

## Related guides

- [Business registry & admin console](./registry-admin.md)
- [Point of sale & stashes](./pos-stash.md)
