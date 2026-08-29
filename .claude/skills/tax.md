---
name: tax
description: Work on the Enterprise POS backend's tax module — global tax setting, per-product override, and tax resolution logic. Use whenever the user asks to add/modify tax endpoints, change how tax is calculated/resolved, or touch backend/src/tax. Also consult this before changing any billing/order calculation that involves tax.
---

# Tax Module (Enterprise POS backend)

NestJS feature module owning the single source of truth for "what tax rate applies to this product right now."

## Module layout

```
src/tax/
├── dto/               # SetGlobalTaxDto, SetProductTaxDto
├── entities/
├── tax.controller.ts
├── tax.service.ts      # resolveTaxPercentage() lives here
├── tax.repository.ts
└── tax.module.ts
```

## Endpoints (base `/api/v1`)

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/tax/global` | auth | active global tax |
| PUT | `/tax/global` | ADMIN | `{ percentage }` |
| PATCH | `/tax/products/:id` | ADMIN | `{ taxPercentage }` |

## Tax resolution algorithm (docs/ARCHITECTURE.md §3 — canonical, do not reinvent)

```
resolveTaxPercentage(product):
    if product.taxPercentage is not null  → use product.taxPercentage
    else                                   → use active GlobalTaxSetting.percentage
```

Critical: resolution happens **at order time**, and the resolved rate is snapshotted into `order_items.taxPercentage`. This means:
- Changing the global tax rate or a product's override must **never** retroactively change totals on past orders/invoices.
- Any code that needs "the tax rate for this order line" after the order exists must read it from the snapshotted `order_items.taxPercentage`, never re-resolve it from current product/global state.

## Conventions to preserve

- Only one `GlobalTaxSetting` row should be "active" at a time — `PUT /tax/global` should update/replace the active setting, not accumulate an unbounded history unless the schema is explicitly versioned for that.
- `PATCH /tax/products/:id` sets `taxPercentage` to `null` to clear an override (falling back to global) — support that explicitly rather than requiring a numeric value always.
- Keep `resolveTaxPercentage` as a single exported function/service method so `orders` and `products` both call the same logic instead of each reimplementing it.
