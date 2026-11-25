# Phase 2 — integration notes and pilot test script

Built from `docs/phase-2/PLAN.md`; workstream reports in `docs/phase-2/reports/`. **Not compiled or run yet** (no network or toolchain in the sandbox where it was written). Expect compile fixes on first build.

## Integrator changes on top of the workstreams

- Fixed two wrong relative imports in `features/pos/presentation/` (`pos_ticket_panel.dart`, `pos_product_grid.dart`).
- Floor plan "Start order" opens `/pos?tableId=…`; the router passes `tableId` to `PosScreen`.
- Menu editor saves modifier groups and combos with `PUT` (the backend replaces them; it has no `PATCH`).
- **Approvals are single-use**: new `approvals.consumedAt`; `assertApproved` consumes atomically and returns 403 `APPROVAL_USED` on reuse. Spec added. (An approval consumed by a request that later fails must be asked for again.)
- `order_items.createdAt` added; order lines load in entry order.
- `POST /invoices/generate` returns the order's existing ISSUED invoice instead of numbering a second one.
- Business day starts at **05:00** outlet time by default (`businessDateFor`).
- Seeded Single Malt 12Y 60 ml at ₹540 (POS board).
- `Order.invoiceNumber` is nullable until payment: Swagger entity and the dashboard's recent-orders list handle it.

## Decisions taken (confirm with your accountant / ops)

- No discounts on liquor lines (`LIQUOR_DISCOUNT_NOT_ALLOWED`).
- Service charge is **not taxed** in Phase 2.
- Cash change = tendered − amount − tip (matches the POSPay board).
- Rounding to the nearest rupee (`roundOff` shown on the bill).
- Legacy orders are backfilled as `TAKEAWAY`, their items as `SENT`.
- 86'd items stay visible on the POS, greyed out.

## Run it

```bash
cd backend && npm install && npx prisma migrate dev && npm run seed && npm test
cd ../print-agent && npm install && npm run build     # then: API_BASE_URL=… DEVICE_KEY=… npm start
cd ../frontend && flutter pub get && flutter test && flutter run -d chrome
```

## Pilot test script

1. Admin → Settings → Hardware: the three seeded printers show; set real IPs; **Test** each. Settings → Devices: register a `PRINTER` device, run the print agent with that key on the outlet LAN.
2. Floor plan → R4 (Rooftop, +10%) → Start order → 4 covers.
3. POS: 2 × Premium Lager (BOT), Chicken Wings (KOT), Classic Mojito between 17:00–20:00 (happy hour −30%), Single Malt 12Y 60 ml → "On the rocks" → seat 2. Ticket panel totals match the server.
4. **Send KOT/BOT** → one BOT at the bar printer, one KOT at the kitchen printer; items show "BOT sent" / "KOT sent".
5. Discount 20% on the whole bill as a Captain (limit 10%) → "A manager must approve" → Manager PIN → applied to food only. Try to reuse the same approval → refused.
6. Void the mojito (already sent) with a reason → manager PIN → a cancellation ticket prints at the bar.
7. Print bill → R4 shows "Bill printed".
8. Pay → By seat → seat 2: cash ₹500 + UPI (ref) + 5% tip → change shown → Complete seat 2 → drawer opens.
9. Pay the rest by card → order PAID with invoice `INV/2026-27/000001`; R4 → Cleaning → set Free.
10. Day close: X report mid-shift; Z report with cash counted → expected vs counted; second Z the same day → refused; Z with an open order → refused unless forced.
11. Offline: disconnect, take a takeaway order → "Offline — 1 order will sync" → reconnect → it syncs once (no duplicate).

## Known gaps

- Not built in the UI: whole-order void, shared items across seats in "By item" split, transfer items into an existing order.
- No specs yet for move, merge, transfer, refund, cash drawer.
- Print jobs are queued outside the order transaction (a failed order can leave a queued ticket).
- Manager PIN check is a copy of the Phase 1 lockout rule in `approvals.service.ts` (could move to a shared `verifyStaffPin`).
- Print agent prints ASCII only (Tamil text shows as `?`).
- Phase 1b tenant-scoping follow-up still open for main's older models.
