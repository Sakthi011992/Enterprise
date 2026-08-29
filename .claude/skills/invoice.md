---
name: invoice
description: Work on the Enterprise POS backend's invoice module — thermal 80mm HTML receipts and A4 PDF invoice generation/reprint. Use whenever the user asks to add/modify invoice templates, printing endpoints, PDF generation, or touches backend/src/invoice.
---

# Invoice Module (Enterprise POS backend)

NestJS feature module that renders an existing order as a printable invoice. It does not create or mutate orders/payments — it's read-only presentation of order state.

## Module layout

```
src/invoice/
├── templates/            # thermal 80mm HTML template, A4 layout
├── invoice.controller.ts
├── invoice.service.ts     # HTML render + PDF generation (Puppeteer or equivalent)
└── invoice.module.ts
```

## Endpoints (base `/api/v1`)

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/invoice/:orderId/thermal` | auth | 80mm printer-friendly HTML |
| GET | `/invoice/:orderId/pdf` | auth | A4 PDF download |

## Workflow (docs/ARCHITECTURE.md §6)

```
Order created (status=PENDING)
  → Payment recorded → status becomes PAID or PARTIALLY_PAID
  → Invoice available via the two GET endpoints above
Reprint: same endpoints, idempotent — calling them again must produce
an identical invoice, never regenerate an invoice number or mutate order state.
```

## Conventions to preserve

- Both endpoints are pure reads: fetch the order (with items + payments, via the `orders` module/repository), render, return. No side effects, no status changes, no new DB rows.
- Money/tax figures shown on the invoice must come from the **snapshotted** `order_items` values (price, taxPercentage at order time), never re-resolved from current product/tax state — this guarantees old invoices stay stable even after prices or tax config change later (see the `tax` skill for why).
- Thermal template targets 80mm width — keep it plain HTML/CSS suitable for ESC/POS-compatible browser printing, not the same layout as the A4 PDF.
- PDF generation should reuse the same order-rendering data/logic as the thermal HTML (single source of truth for line items/totals), just a different template + rendering pipeline (e.g. Puppeteer or a PDF library) — don't duplicate the calculation display logic between the two.
