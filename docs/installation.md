---
title: Installation
sidebar_position: 2
---

# Installation

## Requirements

Declared with `dependency` in `fxmanifest.lua`:

| Resource | Used for |
| --- | --- |
| `kora_lib` | Callbacks, NUI app shell and dialogs, zones, interactions, blips, entities, progress bar, notifications, logging, Discord delivery, rewards, config registry |
| `kora_sql` | Table creation and all queries |
| `kora_core` | Player data, job and duty, permissions, items and money, shared job registry |
| `kora_inventory` | Shops, stashes, useable items, craft capacity checks |
| `kora_target` | Used directly only for polygon interaction zones and the global card-machine player option |

Used if present, not declared in the manifest:

| Resource | Used for |
| --- | --- |
| `kora_bossmenu` | Business account (`addBusinessMoney`, `removeBusinessMoney`, `getBusinessBalance`) and the boss menu module (`openBossMenu`) |
| `kora_dispatch` | Panic button (`createCall`) |

Both are checked with `GetResourceState(...) == 'started'` when needed. Without `kora_bossmenu`, till sales and card payments cannot credit a business account and the balance shows as unavailable. Without `kora_dispatch` the panic button replies that no dispatch service is available.

## Steps

1. Place `kora_jobcreator` in your resources folder.
2. Start it after the five dependencies:

```cfg
ensure kora_jobcreator
```

3. Tables are created on start by `kora_sql`. See [Database](./database.md).
4. On first boot with an empty database a demo Burger Shot business and `burgershot` job are seeded. See [Libraries and seeds](./libraries.md#seeds).

Server scripts load in a fixed order set in `fxmanifest.lua` (`state` first, `main` last); do not reorder them.
