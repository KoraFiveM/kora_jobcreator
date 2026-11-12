---
title: Configuration
sidebar_position: 7
---

# Configuration

Policy lives in `config.lua` (shared, sent to every client) and `server/config.lua` (server only). Business definitions are not configured here: they are stored in the database and built in-game. Recipes, shop-item lists and seeds are Lua libraries, see [Libraries and seeds](./libraries.md). The config is registered with `kora_lib`'s config registry (`shared/config_registration.lua`).

## Core

| Option | Default | Description |
| --- | --- | --- |
| `Config.debug` | `false` | Draws zones and targets for every client. An admin can also toggle this locally from the console's Debug tab. |
| `Config.adminPermission` | `'admin'` | Permission checked with `exports.kora_core:hasPermission`. Required to create, edit and delete businesses and modules. |
| `Config.command` | `'jobcreator'` | Chat command that opens the console. |
| `Config.notifyTitle` | `'Job Creator'` | Title of notifications. |

## Tills: `Config.pos`

| Option | Default | Description |
| --- | --- | --- |
| `shopSlots` | `50` | Default shelf slots for a till. |
| `shopWeight` | `1000000` | Shelf max weight, applied to every till. |
| `stockSlots` | `50` | Default intake stash slots. |
| `stockWeight` | `1000000` | Intake stash max weight. |
| `currency` | `'cash'` | Default customer account, `cash` or `bank`. |
| `maxPrice` | `1000000` | Highest price an employee or boss may set. |

## Stashes: `Config.stash`

| Option | Default | Description |
| --- | --- | --- |
| `slots` | `50` | Default stash slots. |
| `weight` | `1000000` | Default stash max weight. |

## Card machine: `Config.payment`

| Option | Default | Description |
| --- | --- | --- |
| `item` | `'cardmachine'` | Item that shows the "Take a payment" option on players. |
| `commission` | `0.10` | Fraction (not percent) of each payment paid to the employee. |
| `distance` | `5.0` | Maximum distance between employee and customer, also the target distance. |
| `maxAmount` | `1000000` | Largest amount that can be billed. |
| `account` | `'bank'` | Customer account that is debited. |

Note the units: `Config.payment.commission` is a fraction, while the POS module `commission` and `tax` are percentages.

## Panic button: `Config.panic`

Passed to `kora_dispatch:createCall`.

| Option | Default | Description |
| --- | --- | --- |
| `jobTypes` | `{ 'leo' }` | Job types that receive the call. |
| `code` | `'10-90'` | Call code. |
| `priority` | `1` | Call priority. |
| `icon` | `'Siren'` | Call icon. |

## Duty: `Config.duty`

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `true` | Enables automatic on/off duty at Zone modules that have `controlDuty`. When `false`, the server refuses `setDuty`. |
| `keepDutyInJobVehicle` | `true` | Leaving a zone in a vehicle whose plate starts with the first three characters of the job name (case-insensitive) does not clock the player off. |

## Logs: `Config.logs`

| Option | Default | Description |
| --- | --- | --- |
| `retain` | `500` | Rows kept per business in `kora_jobcreator_logs`. Trimming runs every 15 minutes. |

## Skills: `Config.skills`

Optional gating for recipes. Disabled by default.

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `false` | Enforce `levelRequired` and award `xpGained` on recipes. |
| `getLevel(src, skill)` | reads `skills` metadata | Server-side; must return a number. |
| `addXp(src, skill, amount)` | writes `skills` metadata | Server-side. |

The defaults use `kora_core` `getMetaData` and `setMetaData` on the `skills` key. Replace them to use your own skill resource.

## Discord webhooks: `Config.webhooks`

Defined in `server/config.lua` so URLs are never sent to clients (registered as sensitive, server scope).

| Key | Description |
| --- | --- |
| `default` | Receives every business event. Empty by default. |
| a job name | The code also reads `Config.webhooks[job]` and sends that job's events there too. Only `default` is registered with the config registry, so confirm a job key survives `Kora.config.adopt` on your server (see [Troubleshooting](./troubleshooting.md)). |

A POS module may add a third URL with its `webhook` field. Duplicate URLs are sent once. Webhook URLs on modules are removed from client snapshots; the exports return them (see [Exports](./api/cross-resource-exports.md)). Every log entry is also written to `kora_jobcreator_logs` and `Kora.logging.event` regardless of webhooks. Embed colours are set per category: `sale`, `stock`, `payment`, `craft`, `admin`, `panic`.

## Libraries

`Config.recipes`, `Config.shopItems` and `Config.seeds` are filled by files in `shared/`. Edits take effect after the resource restarts.
