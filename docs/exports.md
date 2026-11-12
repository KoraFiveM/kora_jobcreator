---
title: Exports
sidebar_position: 8
---

# Exports

## Server

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

## Client

| Export | Returns |
| --- | --- |
| `getBusinesses()` | Table keyed by business id of the replicated definitions (module `webhook` removed). |
| `openBusinessMenu()` | Opens the console, as `/jobcreator` does. |
