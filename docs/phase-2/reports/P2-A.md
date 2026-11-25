# P2-A report: data model, migrations, pricing engine, seed (backend)

Status: complete as written. Nothing was compiled, migrated, generated or run (no network): `prisma validate`, `prisma generate`, `prisma migrate`, `tsc` and `jest` are all unverified. Schema relations and column names were cross-checked with a script. Nothing committed.

## Files

Changed:
- `backend/prisma/schema.prisma`: new enums (`OrderType`, `OrderItemStatus`, `TicketKind`, `TicketStatus`, `TableStatus`, `TableShape`, `ApprovalType`, `ApprovalStatus`, `DiscountType`, `PrinterConnection`, `PrintJobKind`, `PrintJobStatus`, `RoundingMode`, `DayCloseKind`); `OrderStatus` gains `OPEN SENT BILLED CLOSED VOID`. New models per PLAN 1.2 (`TaxClass`, `Category`, `ProductVariant`, `ModifierGroup`, `ModifierOption`, `ProductModifierGroup`, `Combo`, `ComboItem`, `PriceRule`, `Area`, `DiningTable`, `OutletSettings`, `OrderDiscount`, `Ticket`, `Printer`, `StationRoute`, `PrintJob`, `Approval`, `DayClose`). `Product`, `Order`, `OrderItem`, `Payment`, `User`, `Tenant`, `Outlet` gain the planned columns and relations. Field names kept.
- `backend/src/common/tenancy/tenant-scope.extension.ts`: 13 new models added to `TENANT_MODELS`.
- `backend/src/prisma/prisma.service.ts`: 13 new delegates added to the loose-create list.
- `backend/prisma/seed.ts`: Phase 1 content untouched. Adds `seedPosDemo(tenantId, outletId)`, called from `main()` before the global tax block.

Created:
- `backend/prisma/migrations/20261125130000_phase2_pos_core/migration.sql`: enums, 19 tables, `products`/`orders`/`order_items`/`payments` columns, indexes, FKs, backfills (see below). Adds the five new `OrderStatus` values but does not use them.
- `backend/prisma/migrations/20261125130100_phase2_order_default/migration.sql`: `orders.status` default becomes `OPEN`.
- `backend/src/common/pricing/pricing.engine.ts`: `priceOrder`, `isWithinSchedule`, and the PLAN 1.3 types. Pure, uses `Prisma.Decimal` and `round2` from `common/utils/money.util.ts`.
- `backend/src/common/pricing/pricing.errors.ts`: `PricingError` with `code`. Codes: `LIQUOR_DISCOUNT_NOT_ALLOWED`, `INVALID_DISCOUNT`, `UNKNOWN_DISCOUNT_ITEM`, `DUPLICATE_LINE_ID`, `INVALID_QUANTITY`, `INVALID_PERCENT`, `INVALID_TIME`, `TAX_COMPONENTS_MISMATCH`.
- `backend/src/common/pricing/business-date.ts`: `businessDateFor(now, timeZone, dayStart = '00:00')` → `"YYYY-MM-DD"`, `toDateOnly()` → UTC-midnight `Date` for `@db.Date`, plus `localParts` and `parseHHMM` helpers.
- `backend/src/common/pricing/pricing.engine.spec.ts`: tax, inclusive tax, happy hour, markup, modifiers, % and flat discounts (including the remainder and the cap), liquor exclusion, voids, service charge, both rounding modes, the POS-board ticket (before and after a 20% discount, with internal-consistency asserts), cross-midnight schedules, business date.
- `docs/phase-2/reports/P2-A.md` (this file).

## What the migrations do

Migration 1, in order: create enums; `ALTER TYPE "OrderStatus" ADD VALUE` ×5; create tables; add columns (`orders.invoiceNumber` made nullable, `order_items.productId` made nullable); backfills; indexes; FKs.
- Default tax classes for every tenant: `GST5` (CGST 2.5 + SGST 2.5), `VAT_LIQUOR` (VAT 20, `isLiquor`), `GST18` (CGST 9 + SGST 9).
- `outlet_settings` row for every outlet (service charge 0, prefixes `A` / `INV`, country `IN`, rounding `NEAREST_1`).
- Legacy `orders.type` set to `TAKEAWAY` (the old billing screen is takeaway, PLAN 1.5).
- Legacy `order_items.grossAmount` = `ROUND(price × quantity, 2)` and `status` = `SENT`.

Migration 2: only the default.

## Decisions and deviations (please check)

1. **Single Malt 12Y is seeded at 60 ml ₹500 base**, not ₹540. PLAN 1.4 lists ₹540, but the exit-test ticket is "₹500 + soda ₹40". With the "With soda" option (+₹40) the ticket reproduces. Change the seed value if ₹540 is the intended base.
2. **Modifier group "How to serve (spirits)"** is seeded with `minSelect 0`, `maxSelect 1`. PLAN says "exactly 1" but does not say whether a choice is required.
3. **Discount engine choices** (PLAN left them open):
   - PERCENT is `round2(gross × value/100)` per eligible line, capped at what the line has left.
   - FLAT is split in proportion to each line's remaining capacity. With a single discount that equals gross. Remainder goes to the line with the largest capacity (first one on a tie).
   - `discountableBase` = Σ gross of non-liquor, non-voided lines.
4. **Inclusive tax**: `gross = round2(round2(unit ÷ (1+rate)) × qty)`, as PLAN states. For qty > 1 this can differ by a few paise from `round2(unit × qty ÷ (1+rate))`.
5. **Schedules**: `start === end` never matches. A window that crosses midnight takes the late part on the weekday it started and the after-midnight part on the previous weekday. A null start or end means all day, with the days check still applied.
6. **Business date**: `businessDateFor` defaults `dayStart` to `00:00`. The data model has no per-outlet day-start setting. A bar may want `04:00`. Planner to decide before P2-C uses it.
7. **Snapshot references without FKs**: `order_items.variantId`, `order_items.taxClassId`, `order_items.comboId`, `combo_items.variantId`. A hard delete of a variant, tax class or combo therefore cannot fail on past orders.
8. **User references are real relations** (`cashier` / `waiter` / `createdBy` / `requestedBy` / `approver` / `approvedBy`). Where a model has two relations to User the relation is named (`OrderCashier`, `OrderWaiter`, `DiscountCreatedBy`, `DiscountApprovedBy`, `ApprovalRequestedBy`, `ApprovalApprover`). `StationRoute` uses named relations to Printer as well.
9. **`Product.taxClass` / `Category.taxClass` / `Combo.taxClass`** use `ON DELETE SET NULL`. The 409 `TAX_CLASS_IN_USE` rule is P2-B's job, not a database one.
10. **Seed**: printers are `Counter receipt` (.30, receipt), `Main bar BOT` (.31) and `Kitchen KOT` (.32), all LAN port 9100. Station routes: BAR → Main bar BOT, KITCHEN → Kitchen KOT. Areas: Indoor, Rooftop (+10%), Bar counter. Tables: R1–R9 (Rooftop), T1–T4 (Indoor), Bar 1–10 (Bar counter). Happy hour 17:00–20:00 30% off Cocktails, all outlets. Outlet service charge 5% dine-in, rounding `NEAREST_1`. Seed is idempotent: lookup-first or upsert on the unique key.

## Stubs

None. Everything in PLAN 1.2, 1.3, the P2-A steps and the exit-test ticket is implemented. Not included: no `ProductVariant`/`ModifierOption` `tenantId` (not in the plan's model shapes and not in `TENANT_MODELS`), and no combos in the seed (not in the plan's demo list).

## Risks

1. **Nothing has been compiled or run.** Start with `npx prisma validate && npx prisma generate && npx prisma migrate dev` against a scratch database, then `npx jest pricing`. If Prisma reports drift, the likeliest spot is the new `Order` / `OrderItem` / `Payment` columns, which were written by hand.
2. **Migration needs PostgreSQL 12+**, because `ALTER TYPE ... ADD VALUE` runs in the same migration as other statements. Postgres 12+ allows that inside a transaction, as long as the new values are not used there. They are not used in migration 1.
3. **Legacy row backfills are assumptions**: `type = TAKEAWAY`, items `SENT`. Revert the two `UPDATE`s if the business disagrees.
4. **Phase 1 code that will not typecheck against the new types** (outside P2-A, not touched):
   - `backend/src/modules/orders/entities/order.entity.ts` declares `invoiceNumber: string`, while Prisma now types `Order.invoiceNumber` as `string | null`. Needs `?`/`| null` or a guard in any mapper.
   - Anything reading `OrderItem.productId` as `string` (now `string | null`): `modules/reports/reports.service.ts` line 36 groups by `productId`.
   - `modules/orders/orders.service.ts` still writes legacy `invoiceNumber` on creation. Fine for the type, but P2-C will replace this path.
5. **Invoice numbering check (P2-C)**: the seeded `InvoiceCountryProfile` for `IN` has `numberPrefix: 'GST'` and `FINANCIAL_YEAR` reset. PLAN's exit test expects `INV/2026-27/000001`. P2-C should use the outlet's `invoicePrefix` as PLAN 1.4 says and confirm the profile prefix is not used.
6. **Engine error codes are for P2-C to map** to API errors (`PricingError.code` → `{ code }` response). Nothing in P2-A catches them.

## Requests for other workstreams

- **P2-B**: `Area`, `DiningTable`, `Printer`, `StationRoute`, `PrintJob` relations and `ProductVariant` writes need `TENANT_MODELS`-scoped services as usual. `StationRoute` upserts need `outletId_station` (the unique name). `Product.categoryId`/`taxClassId` are now real FKs.
- **P2-C**: use `priceOrder`, `isWithinSchedule` and `businessDateFor` from `common/pricing`. Map `PricingError.code` to API errors. Set `Order.type` explicitly on every new order (DB default is `DINE_IN`, legacy `POST /orders` must send `TAKEAWAY`). `Order.status` default is `OPEN` after migration 2. Dayclose totals should join `Order.dayCloseId`.
- **Planner**: decide the business day start (see decision 6), the Single Malt price (decision 1), and whether PLAN's `Order.openedAt` should be `createdAt` (the schema has no `openedAt`).

## Memory

No memory was used for this task.
