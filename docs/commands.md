---
title: "Commands"
sidebar_position: 4
---


# Commands

One chat/console command, client-side, unrestricted at the command layer — access is enforced inside the console it opens, not by who may type the command.

## Built-in commands

### `/jobcreator`

Opens the Job Creator NUI console. An administrator (`Config.adminPermission`, default `admin`) sees the full business directory and may create/edit/delete businesses and modules. A non-admin with a boss grade for at least one business sees only the businesses they manage (balance, activity log, prices). A player with neither is told "You do not manage any business." and nothing opens.

| Field | Details |
| --- | --- |
| Context | In-game · client command (`Config.command`) |
| Arguments | No arguments. |
| Access | Anyone may run the command; what it shows depends on `kora_core` admin permission or job-boss grade, both re-checked server-side on every action inside the console. |

**Example**

```text
/jobcreator
```

**Result**

Opens the `kora_jobcreator:management` NUI app on the Businesses tab (or directly on a business's Overview tab if reopened mid-edit).

## Console and in-world UI

### Command summary

| Command | Access | Description |
| --- | --- | --- |
| `/jobcreator` | Everyone to run it | Opens the management console. The name is `Config.command`. An admin sees all businesses; a boss sees the businesses of their job; anyone else gets "You do not manage any business." The command is registered as unrestricted, so access is decided by the checks below. |

### Console

The console is a `kora_lib` app (id `kora_jobcreator:management`).

- **Businesses** view: searchable cards with job, module count and staff present. Admins also get "Create business" (name and job).
- **Business** view: tabs.
  - **Overview** - balance (from `kora_bossmenu`, or "Unavailable"), module count, staff present, business id, job, revision and management level. Admins can rename or reassign the business and delete it. Renaming changes the label only; the id never changes.
  - **Activity** - the latest log rows (up to 50 are requested).
  - **Modules** (admin only) - module cards with "Add module", "Edit data", "Rebuild" and "Delete".
  - **Debug** (admin only) - copy business or module JSON, and toggle zone and target outlines on that admin's own client.

Adding a module asks for its type, then its anchor, then whether it wants a blip, then type-specific fields. Anchors are placed in the world with the `kora_lib` tools (zone creator for sphere, box and poly; placement tool for prop, ped and vehicle; or aiming at an existing object and pressing E). Placement actions close the console first and reopen it on the same business and module afterwards. "Edit data" shows the module as JSON and saves it through the normal validation. "Rebuild" changes type or placement.

### In-world interactions

Target options are created from module definitions. See [Modules](./modules.md) for what each type adds. The card machine option appears on other players for anyone holding `Config.payment.item`.

Notifications use the title `Config.notifyTitle`. Dialogs and menus use `kora_lib` NUI.
