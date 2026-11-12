---
title: Permissions
sidebar_position: 9
---

# Permissions

The resource does not define ACE entries. Access is decided on the server from `kora_core` data.

| Capability | Who |
| --- | --- |
| Create, rename, reassign and delete businesses; list jobs; read and save modules | A player for whom `exports.kora_core:hasPermission(src, Config.adminPermission)` is true |
| Read a business's activity log and balance | Admin, or a boss of the business job (the player's job grade has `isboss`) |
| Set till prices | Admin or boss, and near the till |
| Restock a till | Employee of the job and near the till |
| Open a till as a customer | Anyone, except when `hideWhenStaffed` is set and on-duty staff are present (job members are exempt) |
| Open a stash | Job members; anyone if `public` |
| Use a crafting bench | Job members; anyone if `public`; always near the bench |
| Use the boss menu option | Boss of the job (client check; opening is handled by `kora_bossmenu`) |
| Panic button | On-duty employee of the job near the till |
| Automatic duty and presence | Job members only, verified by job, duty and server-side position |
| Card machine billing | Any player whose job matches a business; see [Troubleshooting](./troubleshooting.md) |

Admins who are not members of the job cannot restock or use job-locked modules unless the module is `public`.
