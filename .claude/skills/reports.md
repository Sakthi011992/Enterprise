---
name: reports
description: Work on the Enterprise POS backend's reports module — dashboard metrics (today/monthly revenue and tax), top-selling products, recent orders. Use whenever the user asks to add/modify reporting or dashboard endpoints, or touches backend/src/reports.
---

# Reports Module (Enterprise POS backend)

NestJS feature module, ADMIN-only, providing read-only aggregate views over orders/payments.

## Module layout

```
src/reports/
├── dto/
├── entities/               # DashboardEntity, TopProductEntity, etc.
├── reports.controller.ts
├── reports.service.ts       # aggregation queries
├── reports.repository.ts
└── reports.module.ts
```

## Endpoints (base `/api/v1`, ADMIN only)

| Method | Path | Notes |
|---|---|---|
| GET | `/reports/dashboard` | today orders/revenue/tax, monthly revenue/tax |
| GET | `/reports/top-products?limit=10` | top selling products |
| GET | `/reports/recent-orders?limit=10` | recent orders |

## Conventions to preserve

- These are read-only, aggregation-heavy queries — prefer Prisma aggregate/groupBy queries (or raw SQL if Prisma's query API can't express it cleanly) over pulling all rows into Node and summing in memory, for performance as order volume grows.
- Revenue/tax figures must be computed from the same snapshotted `order_items` fields used by `orders` and `invoice` (price, taxPercentage, lineTotal at order time) — reports must never silently diverge from what's shown on an actual invoice.
- "Today" and "monthly" windows should respect the server's configured timezone consistently — don't mix UTC and local-time boundaries between the two figures.
- `limit` query params on `top-products` / `recent-orders` should have a sane default (10) and a hard cap to avoid unbounded queries.
- Only count orders that have progressed past PENDING (i.e. have at least one payment / are PAID or PARTIALLY_PAID) as "revenue" unless the user explicitly asks reports to include pending/unpaid orders too.
