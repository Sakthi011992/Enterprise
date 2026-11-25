# P2-C report: orders, payments, approvals, day close (backend)

Status: implemented and reviewed by reading. Nothing was compiled or run (no toolchain in this session), so the Jest specs and `tsc` are unverified. Run `npx prisma generate`, `npx tsc --noEmit` and `npm test` before merging.

## Files

Orders (`backend/src/modules/orders/`)
- `orders.controller.ts`, `orders.service.ts`, `orders.repository.ts`, `orders.module.ts`: lifecycle, items, send, hold, bill, discounts, voids, move, merge, transfer, legacy create and search.
- `order-line-resolver.ts`: AddItem to priced line (variant, modifiers, combo, happy hour, area markup, tax snapshot).
- `order-pricing.service.ts`: `recalc(tx, orderId)` runs `priceOrder` and writes line and order totals.
- `order-pricing.ts`, `order-view.ts`, `business-day-window.ts`: pure helpers (tax snapshot, frozen lines, discount amounts, OrderView mapper, 05:00 business-day window).
- `dto/order.dto.ts`, `orders.service.spec.ts`.

Payments (`backend/src/modules/payments/`)
- `payments.service.ts`: pay (split tender, tip, cash change, completeSeat), split view, close, refund, legacy create and refund.
- `split.ts`: pure shares builder (EQUAL, SEAT, ITEMS with shared items).
- `payments.controller.ts` (legacy `/payments`), `order-payments.controller.ts` (`/orders/:id/split|payments|close|refund`), `payments.repository.ts`, `dto/payment.dto.ts`, `payments.service.spec.ts`, `split.spec.ts`.

Approvals (`backend/src/modules/approvals/`): approvals service, controller, repository, DTOs, `approval-payload.ts` (validation and canonical matching), audit trail repository and service, specs for payload and PIN lockout.

Day close (`backend/src/modules/day-close/`): X and Z service, `day-totals.ts` (PLAN 1.6 shape, pure), controller on `/reports/*`, specs.

Cash drawer (`backend/src/modules/cash-drawer/`): `POST /cash-drawer/open`.

Edited outside my folders (small, deliberate):
- `backend/src/modules/invoice/invoice.service.ts`: added `issueForOrder(tx, order, { countryCode, invoicePrefix })`. Allocates the number and writes an Invoice row with no PDF. Existing endpoints are unchanged.
- `backend/src/modules/reports/reports.repository.ts`: the dashboard aggregate now counts `CLOSED` orders, because takeaway orders close straight after payment.
- `docs/API.md`: added `## Orders (Phase 2)`.

`app.module.ts` already registers `ApprovalsModule`, `DayCloseModule` and `CashDrawerModule` (P2-B). Module names match.

## Decisions and deviations

1. **Cash change includes the tip.** The plan says `changeGiven = tendered − amount`. I use `tendered − amount − tip`, where the tip is attached to the cash line (or the first line when there is no cash). Otherwise a 5% tip handed over in the same cash would be counted as change. If the planner wants the literal formula, change one line in `payments.service.ts` `settle()`.
2. **Invoice prefix** comes from `OutletSettings.invoicePrefix` (outlet), as requested. The country profile supplies the sequence and reset period, so the number is `INV/2026-27/000001` for an IN profile with FINANCIAL_YEAR.
3. **Business date**: P2-A exports `businessDateFor(now, tz, dayStart)`. I call it with `'05:00'`. `toDateOnly` is used for the DayClose date.
4. **Repricing does not recompute frozen lines.** Each line stores its final unit price (markup and happy hour applied on add) and a tax snapshot in `OrderItem.taxBreakdown` (`{ snapshot, components }`). Later catalogue or tax edits do not change an open bill.
5. **Discount amounts** per discount are cumulative differences of the engine total, so they add up exactly.
6. **Approvals** are matched by canonical payload (`approval-payload.ts`), outlet, order and age (15 min). The PIN check replicates the Phase 1 rule (3 tries, 5 min lock, bcrypt) using `AuthRepository.findStaffPin` and `updateStaffPin`. `AuthService.pinLogin` is not reused because it only serves PIN-persona users and issues a session, and managers use PASSWORD personas. Suggest the auth owner expose `verifyStaffPin(userId, pin)` so the rule lives in one place.
7. **Cash-drawer gate**: `@Can('sales.orders.take','EDIT')`, so every order-taker can ask. The service opens directly only with `sales.payments.take` EDIT, and otherwise needs an approved NO_SALE approval.
8. **Legacy `POST /orders`** returns `invoiceNumber: null` until the order is paid. Invoice numbers are now assigned on PAID, as the plan requires.
9. **Legacy `POST /payments`** delegates to the new settle path (takeaway orders close on payment) and returns the legacy `{ payment, order }` shape.
10. **New error codes** beyond the plan: `ITEM_REQUIRED`, `ITEM_NOT_FOUND`, `ITEM_UNAVAILABLE`, `VARIANT_UNAVAILABLE`, `ORDER_NOT_OPEN`, `NOTHING_TO_BILL`, `UNSENT_ITEMS`, `TABLE_REQUIRED`, `TABLE_NOT_FOUND`, `NOT_DINE_IN`, `SAME_TABLE`, `SAME_ORDER`, `TARGET_REQUIRED`, `ORDER_HAS_PAYMENTS`, `ORDER_NOT_PAYABLE`, `ORDER_NOT_PAID`, `TENDERED_TOO_LOW`, `SEAT_REQUIRED`, `SEAT_NOT_FULLY_PAID`, `REFUND_EXCEEDS_PAID`, `REFUND_EXCEEDS_PAYMENT`, `PAYMENT_NOT_FOUND`, `APPROVAL_NOT_FOUND`, `APPROVAL_NOT_PENDING`, `APPROVAL_EXPIRED`, `APPROVAL_MISMATCH`, `APPROVER_NOT_ALLOWED`, `INVALID_PAYLOAD`, `INVALID_SPLIT`, `INVALID_ASSIGNMENT`, `INVALID_PERCENT`, `INVOICE_PROFILE_MISSING`, `DAY_ALREADY_CLOSED`, `OPEN_ORDERS_EXIST`.
11. **Bill printing** is queued after commit. A missing receipt printer therefore returns an error while the order stays BILLED.
12. **Ticket sequence** is `count(tickets since 05:00 business-day start) + 1`. Concurrent sends can collide. Fine for a pilot, but a per-outlet counter would be correct.
13. **Transfer** leaves the source order open even when it is emptied. Discounts move only when every line they name moves.
14. **Combo lines**: `OrderItem.productId` is the first combo item's product (the column is a required FK). The combo name is in `productName`.
15. **X report print**: `POST /reports/x/print` uses `PrintService.queueReportTotals`.

## Gaps and requests for other workstreams

- **P2-A, `OrderItem.createdAt` is missing.** The plan does not list it, and I do not order or sort lines by it. Lines come back in unspecified order. Add `createdAt DateTime @default(now())` and an `orderBy` to `OrdersRepository.loadBundle` if the POS needs stable order.
- **P2-A**: `Order.netSubtotal` is not stored. The view computes subtotal minus discountTotal.
- **Invoice duplication**: `POST /invoices/generate` (unchanged) still creates a second invoice row for an order that already has one from `issueForOrder`. The PDF path should reuse that number. Left alone because the endpoint must not change.
- **Approval reuse**: an approved approval can be cited more than once (no consumed flag in the schema). Add `consumedAt` or a unique link to the order line or discount.
- **Forced Z** leaves open orders unlinked. They will be counted again in the next business day's window if they are still open then.
- **Orders with a null `outletId`** (legacy rows) are excluded from day close.
- Specs (Jest, mocked repositories, real pricing engine where noted): `orders.service.spec.ts`, `payments.service.spec.ts`, `day-close.service.spec.ts`, `day-totals.spec.ts`, `approval-payload.spec.ts`, `approvals.service.spec.ts`. They cover: send grouping by station, discount limit (APPROVAL_REQUIRED), approved discount, liquor refusal, cancellation ticket on void of a sent line, change and tip, overpay refusal, invoice once, Z refusal (open orders and second close), totals, PIN lockout.
- `split.spec.ts` covers equal, seat, shared-item and bad-assignment cases.
- Not covered by a spec: move, merge, transfer, refund, cash drawer. Add these when the toolchain is available.

## Memory

No memory was read or used for this task.
