---
title: kora_jobcreator
sidebar_position: 1
---

# kora_jobcreator

`kora_jobcreator` is an in-game job and business creator for Kora servers. A business is a job, an optional perimeter and a list of modules (till, stash, crafting bench, boss desk, prop, map blip, useable item). Businesses are stored in MySQL and built in-game through a `kora_lib` AppShell console, so no config edit or restart is needed to add one: every connected client receives the new definition as soon as it is saved.

Current version: see `version` in `fxmanifest.lua`.

## Features

- **Business console** - `/jobcreator` opens the management app. Admins see every business and can create, rename, reassign and delete them and edit modules; a boss sees only their own business (overview and activity). See [Commands and UI](./commands-and-ui.md).
- **Eight module types** - Zone, Blip, StaticEntity, BossMenu, POS, Stash, Crafting, UseableItem. See [Modules](./modules.md).
- **Tills** - customer shop plus an employee intake stash, fixed or employee-set prices, sales tax, sold-stock commission, optional panic button and a hide-when-staffed rule. Stock itself is owned by `kora_inventory`.
- **Card machine** - an employee bills a nearby player, who approves it; the business account is credited. See [Modules](./modules.md#card-machine).
- **Crafting and useable items** - benches offering recipes from a shared library, and items that roll a weighted reward or run a recipe. See [Libraries and seeds](./libraries.md).
- **Duty and presence** - entering a business zone can clock staff on and off; the server tracks who is inside.
- **Logging** - sales, restocks, payments, crafts, panic alarms and admin edits are written to a table, to `kora_lib` logging and optionally to Discord. See [Configuration](./configuration.md).
- **First-boot seed** - a demo Burger Shot business and job. See [Libraries and seeds](./libraries.md#seeds).

## Pages

- [Installation](./installation.md) - dependencies, start order, first boot.
- [Modules](./modules.md) - every module type and its fields, tills and the card machine.
- [Configuration](./configuration.md) - every `config.lua` and server-only option.
- [Libraries and seeds](./libraries.md) - recipes, shop-item lists and business seeds.
- [Commands and UI](./commands-and-ui.md) - the command, the console and in-world interactions.
- [Permissions](./permissions.md) - who may do what.
- [Exports](./exports.md) - server and client exports.
- [Events and callbacks](./events.md) - network events, server and client callbacks, handled events.
- [Database](./database.md) - tables and columns.
- [Items](./items.md) - items the resource uses or expects.
- [Troubleshooting](./troubleshooting.md) - console messages and common problems.
