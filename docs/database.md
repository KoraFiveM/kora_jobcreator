---
title: Database
sidebar_position: 11
---

# Database

Tables are created and checked on start with `Kora.sql.ensureTables` (`server/tables.lua`); schema warnings are printed to the console. If `kora_sql` is not ready within 60 seconds the resource disables itself. No SQL files are shipped. Shop and stash contents are stored by `kora_inventory`, not here.

## `kora_jobcreator`

One row per business. Primary key `id`; index on `job`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `varchar(64)` | Business id (slug). |
| `label` | `varchar(128)` | Display name. |
| `job` | `varchar(64)` | Job name. |
| `modules` | `longtext` | JSON array of modules. |
| `created_at`, `updated_at` | `timestamp` | Maintained by MySQL. |

## `kora_jobcreator_deleted`

Deletion markers that stop a seed from reappearing. Primary key `id` (`varchar(64)`).

## `kora_jobcreator_prices`

Remembered employee-set prices. Primary key `shop`, `item`.

| Column | Type |
| --- | --- |
| `shop` | `varchar(64)` |
| `item` | `varchar(64)` |
| `price` | `int` unsigned |
| `updated_at` | `timestamp` |

## `kora_jobcreator_logs`

Append-only activity log. Primary key `id` (auto-increment `bigint`); index on `business`, `id`.

| Column | Type | Notes |
| --- | --- | --- |
| `business` | `varchar(64)` | Business id. Rows survive deletion of the business. |
| `category` | `varchar(32)` | `sale`, `stock`, `payment`, `craft`, `admin`, `panic` or a custom one from the export. |
| `message` | `varchar(512)` | Truncated to 512 characters. |
| `citizenid` | `varchar(64)` | Actor, may be null. |
| `amount` | `int` | Optional amount, may be null. |
| `created_at` | `timestamp` | |

Rows beyond `Config.logs.retain` per business are trimmed every 15 minutes.
