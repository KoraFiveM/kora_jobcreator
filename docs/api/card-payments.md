---
title: "Item sales and payments"
sidebar_position: 5
---

# Item sales and payments

## Client

The till's **Take a payment** option opens an Appshell sale builder. It lists the business's Sales Items, shows the employee's on-hand quantity and item image, and lets the employee choose a quantity and unit price. The portable `cardmachine` player target opens the same builder with the selected customer prefilled. The seller chooses a customer from the player list, including themselves.

The buyer receives an itemized Appshell invoice and chooses to pay with cash, pay by card, or decline. Cash debits the `cash` account and card debits the `bank` account. Different players must remain within `Config.payment.distance` when the sale is completed. A till sale requires the employee to be at that till; a portable sale requires the employee to carry the configured card machine item.

Namespace: `Kora.callback` · Source: `client/payment.lua`

## Server

The server validates that the business belongs to the seller's current job, every item is on the business Sales Items list, the seller still has the selected quantities, and the buyer approves the exact invoice. It removes the seller's items and charges the buyer only after approval. Failed payment or business-account credit attempts trigger an item restore and buyer refund.

Namespace: `Kora.callback` · Source: `server/payment.lua`

### Config.payment (`config.lua`)

| Option | Type | Description |
| --- | --- | --- |
| `item` | string | Item required for the portable player target (default `cardmachine`). The till option does not require it. |
| `commission` | number | Fraction of the sale paid to the employee (default `0.10`). |
| `distance` | number | Maximum distance between different seller and buyer players (default `5.0`). |
| `maxAmount` | integer | Hard cap on one sale (default 1,000,000). |

### `Kora.callback.trigger('kora_jobcreator:server:requestPayment', target, businessId, moduleId, items)`

Request an item sale. The buyer can be the seller. The client supplies item names, quantities and unit prices, but the server validates the catalog, inventory and total before asking the customer to approve it.

| Parameter | Type | Description |
| --- | --- | --- |
| `src` | integer | Seller's server id, supplied automatically to the callback. |
| `target` | integer | Buyer's server id. |
| `businessId` | string | Business id whose Sales Items list applies; its job must match the seller's current job. |
| `moduleId` | string or `false` | Till id for an in-world till sale; pass `false` for a portable card machine sale. |
| `items` | table[] | Array of `{ item, amount, unitPrice }` sale lines. |

Returns `true` after a completed sale, otherwise `false, error`. After the buyer approves, `Config.payment.commission` goes to the seller's bank and the remaining proceeds go to the business account. The callback is rate-limited to 5 calls per 15 seconds.

```lua
Kora.callback.trigger('kora_jobcreator:server:requestPayment', 47, 'burgershot', 'burgershot_till', {
    { item = 'burger', amount = 2, unitPrice = 12 },
})
```

### Related guides

- [Point of sale & stashes](./pos-stash.md)
