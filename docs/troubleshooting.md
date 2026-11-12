---
title: Troubleshooting
sidebar_position: 13
---

# Troubleshooting

## Console messages

| Message (prefix `[kora_jobcreator]`) | Meaning |
| --- | --- |
| `kora_sql was not ready; resource disabled.` | `kora_sql` did not become ready within 60 seconds. |
| `schema failed` or `schema <table>: ...` | Table creation or a schema warning from `kora_sql`. |
| `N business(es) live.` | Boot finished. |
| `<id> module #N rejected: ...` | A stored module failed validation and was skipped; edit it in-game or in the database. |
| `skipped business <id>: ...` | The whole business row was invalid. |
| `<id> is assigned to job "x", which is not registered` | Job-locked modules will not appear until the job exists or the business is reassigned. |
| `stash id ... is used by both` / `till id ... is used by both` | Two businesses share an id; the first keeps it. |
| `item ... already has a use handler` | Another business already bound that useable item. |
| `till ... references unknown shop-item list` | The list name is not in `Config.shopItems`. |
| `could not credit ... for a sale` | `kora_bossmenu` is not running or refused; the sale still happened. |

## Common problems

- **A module does not appear.** If the business has a Zone, other modules only exist while you are inside it. Job-locked modules need the right job.
- **Business account unavailable or sales not credited.** `kora_bossmenu` must be started.
- **Panic button does nothing.** `kora_dispatch` must be started and `Config.panic.jobTypes` must match a recipient job type.
- **Seeded business does not return.** Deleting it recorded a marker in `kora_jobcreator_deleted`. Create the same id by hand or remove the marker row.
- **Recipes or shop lists changed but nothing happened.** Libraries load at start; restart the resource.
- **Skill requirements ignored.** They only apply when `Config.skills.enabled` is `true`.

## Behaviours worth knowing

- Server-side, the card machine callback does not check that the employee holds the item, is on duty or is near a till; it only needs a job matching a business. If several businesses share a job, which one is credited depends on table iteration order.
- The Burger Shot seed's comments refer to a `/business` command; the actual command is `/jobcreator` (`Config.command`).
- Only `Config.webhooks.default` is registered with `Kora.config`; the per-job webhook key is read by the code, but whether it survives config adoption is not confirmed from this repository.
