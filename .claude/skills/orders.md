---
name: orders
description: Work on the Enterprise POS backend's orders module — cart-to-order creation, server-side bill calculation, order history/search, order detail. Use whenever the user asks to add/modify order endpoints, billing/checkout logic, invoice numbering, or the money-calculation engine, or touches backend/src/orders.
---

# Orders Module (Enterprise POS backend)

NestJS feature module that owns cart → order creation and is the **sole authority** for money calculations. Nothing about pricing is ever trusted from the client.

## Module layout

```
src/orders/
├── dto/                 # CreateOrderDto ({ items: [{productId, quantity}] })
├── entities/              # OrderEntity, OrderItemEntity
├── orders.controller.ts
├── orders.service.ts       # calculation engine + invoice numbering
├── orders.repository.ts
└── orders.module.ts
```

## Endpoints (base `/api/v1`)

| Method | Path | Role | Notes |
|---|---|---|---|
| POST | `/orders` | auth | `{ items: [{productId, quantity}] }` — totals computed server-side |
| GET | `/orders` | auth | search by invoiceNumber, date range, paginated |
| GET | `/orders/:id` | auth | full detail incl. items + payments |

## Bill calculation (docs/ARCHITECTURE.md §4 — authoritative, server-side only)

Per cart line:
```
lineSubtotal = price × quantity
taxAmount    = round(lineSubtotal × taxPercentage / 100)
lineTotal    = lineSubtotal + taxAmount
```

Order totals:
```
subtotal   = Σ lineSubtotal
taxAmount  = Σ taxAmount
grandTotal = subtotal + taxAmount
```

- Monetary values are `Decimal(12,2)`. Rounding is half-up to 2 decimal places, applied consistently everywhere money is computed — never use floating point for money.
- `price` and `taxPercentage` are **snapshotted onto the order/order_items at creation time** (via the `tax` module's `resolveTaxPercentage`) — the client only ever sends `productId` + `quantity`. Never accept a client-supplied price, tax rate, or total for an order.
- Each order gets a unique, sequential-looking `invoiceNumber` at creation time; it must never be reused or regenerated on reprint.

## Order lifecycle

```
Order created → status = PENDING
Payment recorded (payments module) → if amount == grandTotal: status = PAID
                                     → if amount <  grandTotal: status = PARTIALLY_PAID
```
Status transitions are driven by the `payments` module, not set directly by the orders endpoints — see the `payments` skill.

## Conventions to preserve

- `POST /orders` must re-fetch current product price/active-status/tax from the DB inside the request (never trust cached client data), reject inactive/deleted products, and do the whole calculation + insert in a single DB transaction.
- `GET /orders` supports search by `invoiceNumber` and a date range filter, plus the standard pagination contract (`?page=&limit=&search=` → `{ data, meta }`).
- `GET /orders/:id` must return items and payments together — clients (invoice, reports, order history screens) rely on this single call.
- Unit tests here should cover the calculation engine and tax snapshotting edge cases (zero-tax products, mixed-tax carts, rounding boundaries) per docs/ROADMAP.md Phase 3.
