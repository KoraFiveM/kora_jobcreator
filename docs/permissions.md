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
| Create, edit and delete business recipes, sales items, stores and crafters | Admin |
| Restock a closed shop | Employee of the job and near the till |
| Open a closed shop as a customer | Anyone while no on-duty staff are in the business (job members are exempt). Staffed tills have no customer shelf |
| Pick up from an employee store | Employee of the job, near one of the store's locations |
| Open a stash | Job members; anyone if `public` |
| Use a crafting bench or category | Job members only (`public` does not apply); always near the bench or one of the category's locations |
| Use the boss menu option | Boss of the job (client check; opening is handled by `kora_bossmenu`) |
| Panic button | On-duty employee of the job near the till |
| Automatic duty and presence | Job members only, verified by job, duty and server-side position |
| Itemized payments | Employee of the selected business; at the till, or holding `Config.payment.item` for the portable option |

Admins who are not members of the job cannot restock or use job-locked modules unless the module is `public`.
