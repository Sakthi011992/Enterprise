---
name: payments
description: Work on the Enterprise POS backend's payments module — recording payments against an order, payment method handling, status transitions, refunds. Use whenever the user asks to add/modify payment endpoints, refund logic, or order-status-on-payment behavior, or touches backend/src/payments.
---

# Payments Module (Enterprise POS backend)

NestJS feature module for recording payments and driving order status.

## Module layout

```
src/payments/
├── dto/                 # CreatePaymentDto, RefundDto
├── entities/
├── payments.controller.ts
├── payments.service.ts    # status-transition logic lives here
├── payments.repository.ts
└── payments.module.ts
```

## Endpoints (base `/api/v1`)

| Method | Path | Role | Notes |
|---|---|---|---|
| POST | `/payments` | auth | `{ orderId, amount, paymentMethod }` → updates order status |
| GET | `/payments/order/:orderId` | auth | payments for an order |
| POST | `/payments/:id/refund` | ADMIN | mark refunded |

Supported `paymentMethod` values: cash, UPI, credit, debit.

## Status transition rule (docs/ARCHITECTURE.md §6)

```
Payment recorded ──► if sum(payments.amount) == order.grandTotal → order.status = PAID
                     if sum(payments.amount) <  order.grandTotal → order.status = PARTIALLY_PAID
```

- Support multiple partial payments against one order; recompute status from the running sum of non-refunded payments each time a payment is recorded.
- `POST /payments/:id/refund` marks the payment refunded (don't hard-delete the payment row — it's part of the audit trail) and must recompute the order's status accordingly (e.g. back to `PARTIALLY_PAID` or `PENDING`).

## Conventions to preserve

- Reject payments that would push the paid total above `order.grandTotal` unless the product/business rules explicitly allow overpayment — if unsure, ask rather than silently allowing it.
- All payment amounts use the same `Decimal(12,2)` / half-up rounding convention as `orders`.
- ADMIN-only for refunds; regular authenticated (cashier) users can record payments but not refund them.
- This module never touches invoice generation directly — the `invoice` module reads order/payment state, it doesn't get called from here.
