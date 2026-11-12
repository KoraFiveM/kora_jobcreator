---
title: Events and callbacks
sidebar_position: 10
---

# Events and callbacks

Callbacks use `Kora.callback`. Every server callback has a rate limit, shown as maximum calls per window in milliseconds.

## Net events

| Event | Direction | Description |
| --- | --- | --- |
| `kora_jobcreator:client:sync` | server to client | Full replacement list of business definitions. Sent to everyone on boot and after every change, and to a player on `QBCore:Server:PlayerLoaded`. The client rebuilds a business only when its `rev` changed. |
| `kora_jobcreator:client:staff` | server to client | Table of business id to staff count. |
| `kora_jobcreator:server:leaveAll` | client to server | Sent when a client stops this resource; clears that player's presence. |

## Handled events

| Event | Where | Use |
| --- | --- | --- |
| `QBCore:Server:PlayerLoaded` | server | Sends the current snapshot to that player. |
| `QBCore:Server:OnPlayerUnload`, `playerDropped` | server | Clears presence (and a pending card payment on drop). |
| `QBCore:Server:OnJobUpdate`, `QBCore:Server:SetDuty` | server | Re-validates presence; going off duty clears it. |
| `QBCore:Client:OnJobUpdate` | client | Re-sends enter or leave for businesses the player is inside, and refreshes the console. |
| `kora_inventory:server:sessionClosed` | server | Closing a till's intake stash triggers restocking. |
| `kora_inventory:server:audit` | server | Action `purchase` credits the business and pays commission. |
| `onClientResourceStop` | client | Tears down props and targets. |

The resource also registers a `swapItems` hook on `kora_inventory` that blocks dropping items a till does not accept into its intake stash.

## Server callbacks

| Callback | Arguments | Limit | Purpose |
| --- | --- | --- | --- |
| `kora_jobcreator:server:hydrate` | none | 5 per 10000 | Snapshot, staff counts, admin flag, ready flag. |
| `kora_jobcreator:server:jobs` | none | 5 per 10000 | Admin: job list for selects. |
| `kora_jobcreator:server:createBusiness` | payload | 5 per 30000 | Admin: create a business. |
| `kora_jobcreator:server:editBusiness` | businessId, payload | 10 per 30000 | Admin: rename or reassign. |
| `kora_jobcreator:server:deleteBusiness` | businessId | 5 per 30000 | Admin: delete and mark as deleted. |
| `kora_jobcreator:server:module` | businessId, index | 10 per 10000 | Admin: one module for editing. |
| `kora_jobcreator:server:saveModule` | businessId, index or nil, payload | 20 per 30000 | Admin: add or replace a module. |
| `kora_jobcreator:server:removeModule` | businessId, index | 20 per 30000 | Admin: remove a module. |
| `kora_jobcreator:server:logs` | businessId, limit | 10 per 10000 | Admin or boss: recent log rows (1 to 100, default 25). |
| `kora_jobcreator:server:balance` | businessId | 10 per 10000 | Admin or boss: balance from `kora_bossmenu`. |
| `kora_jobcreator:server:enter`, `kora_jobcreator:server:leave` | businessId | 20 per 10000 | Staff presence. |
| `kora_jobcreator:server:setDuty` | businessId, onDuty | 10 per 10000 | Automatic duty. |
| `kora_jobcreator:server:openStash` | stashId | 10 per 10000 | Open a stash. |
| `kora_jobcreator:server:openShop` | shopId | 10 per 10000 | Open a till as a customer. |
| `kora_jobcreator:server:openStock` | shopId | 10 per 10000 | Open the intake stash. |
| `kora_jobcreator:server:tillPrices` | shopId | 10 per 10000 | Boss: shelf price list. |
| `kora_jobcreator:server:setTillPrice` | shopId, slot, price | 20 per 10000 | Boss: reprice a non-fixed item. |
| `kora_jobcreator:server:panic` | businessId, shopId | 3 per 30000 | Send a dispatch call. |
| `kora_jobcreator:server:craft` | businessId, moduleIndex, recipeId | 20 per 10000 | Craft a recipe. |
| `kora_jobcreator:server:requestPayment` | target server id | 5 per 15000 | Card machine billing. |

## Client callbacks

Asked by the server during a flow.

| Callback | Purpose |
| --- | --- |
| `kora_jobcreator:client:setPrice` | Price prompt during restocking. |
| `kora_jobcreator:client:billAmount` | Amount prompt for the employee. |
| `kora_jobcreator:client:approveBill` | Approval dialog for the customer. |
