---
title: "Card payments"
sidebar_position: 5
---


# Card payments

## Client

The portable card machine is registered once globally with `kora_target:addGlobalType('player', ...)` (not per business), gated on the employee carrying `Config.payment.item` (default `cardmachine`) and being within `Config.payment.distance` of the target player. Two client callbacks collect the one piece of information each side must supply: `kora_jobcreator:client:billAmount` (employee) and `kora_jobcreator:client:approveBill` (customer) — the server drives the flow and decides the outcome; the client dialogs never decide anything themselves.

Namespace: `Kora.callback (server)` · Source: `client/payment.lua`

### Functions

No client exports here — see KoraJobCreator.takePayment / openPriceEditor under Cross-resource exports for the two internal entry points another client script could in principle call.

## Server

Validates and settles one card payment: funds move, commission is split, and the business account is credited, with rollback if the business side fails.

Namespace: `Kora.callback (server)` · Source: `server/payment.lua`

### How it works

Wrapped in `pcall` with `table.pack`/`table.unpack` specifically so that any rejection reason returned mid-flow (not just a thrown error) survives being captured — a bare two-value `local ok, err = pcall(...)` would silently drop every `(false, reason)` the body returns on a handled rejection.

### Config.payment (config.lua)

Pass an options table as the final argument to a play function. Omit the table or any field to use its default.

| Option | Type | Description |
| --- | --- | --- |
| `item` | string | Item required to take a payment (default `cardmachine`). |
| `commission` | number | Fraction of every manual payment paid to the employee (default `0.10`). |
| `distance` | number | Both players must be within this many metres of each other (default `5.0`), checked both before and after the dialogs. |
| `maxAmount` | integer | Hard cap on one payment (default 1,000,000). |
| `account` | string | Account the customer is billed from (default `bank`). |

### Functions

1 server callback.

#### `Kora.callback.trigger('kora_jobcreator:server:requestPayment', target)`

An employee bills a nearby player with the portable `cardmachine` item (a global item, not tied to any till). Both halves of the transaction are confirmed by their own owner — the employee names the amount, the customer independently approves it — and distance between them is re-checked AFTER both dialogs answer, since a player can walk away mid-dialog.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. Supplied automatically as the first argument of a `Kora.callback.register` handler — never passed by the client. |
| `target` | integer | The customer's server id. |

**Returns**

- **ok** — true once the customer has been charged and the business credited.
- **err** — `'You already have a payment in progress.'`, `'You are not working for a business.'` (caller's job matches no business), `'Pick someone else.'`, `'That player is not around.'`, `'They are too far away.'`, `'That amount is not valid.'`, `'The payment was declined.'` (customer declined or their dialog timed out), `'They walked away.'`, a kora_core money-removal reason, or `'The business account is unavailable.'` (the customer and employee are both made whole if this happens after the charge).

**Example**

```lua
Kora.callback.trigger('kora_jobcreator:server:requestPayment', 47)
```

**Representative console output**

```text
On success: `Config.payment.commission` (default 10%) of the amount goes straight to the employee's bank, the remainder is credited to the business account, and both players are notified. Rate-limited to 5 per 15s.
```

### Related guides

- [Point of sale & stashes](./pos-stash.md)
