# Phase 3 — integration notes

Plan: `docs/phase-3/PLAN.md`. Workstream reports: `docs/phase-3/reports/P3-A..E.md`.

## What landed

| Area | Backend | Frontend |
|---|---|---|
| Data model | 25 new models/enums, migration `20261125160000_phase3_bar_stock` (default stock locations per outlet, `kds.bump` permission, old tickets marked SERVED) | — |
| Stock core | `modules/stock-core`: ledger (`post`, `deductForSentItems`, `reverseSale`), weighted average cost, auto-86 / auto un-86, below-par alerts, document numbers | `features/inventory/data/stock_format.dart` (same "8 btl + 410 ml" format) |
| Bar tabs and bottle locker | `modules/tabs`: open (age check, card / deposit / house account / none with manager approval, persona limit), limit enforced on every add, near-limit warning once, close and pay with the deposit applied, move to table, locker store/serve/edit/remove | `/tabs` Bar tabs screen + Open tab dialog, tab badge and limit error on POS, Open tab on Bar counter |
| KDS | `modules/kds`: board per station, Start / Bump / Recall / Served, all-day counts, average ticket time, ready alerts to the waiter, overdue alert after 5 min | `/kds` Kitchen display, `/service/ready` Ready to serve |
| Realtime | `modules/realtime`: socket.io gateway `/rt` (JWT in the handshake, rooms per outlet, station, user) | `core/realtime`: client with reconnect; KDS and ready list poll every 5 / 10 s while disconnected |
| Orders integration | `send` deducts recipes at the line's station, voids reverse the sale and log wastage, tickets and events go out after commit | — |
| Inventory | `modules/inventory`: locations, stock items, par, movements, transfers, counts (save lines / submit / post), wastage (photo above ₹2,000), uploads, variance, kegs, summary KPIs, recipes | `/inventory` (7 tabs), `/inventory/items/:id`, `/stock-count` (offline Hive queue), Log wastage sheet, Recipe section in the product editor, stock column on modifier options |
| Procurement | `modules/procurement`: vendors, POs (draft → approval → sent), reorder suggestions and requests, GRN with debit note / damaged wastage / PO status, debit notes | `/procurement`, `/procurement/reorder`, `/procurement/po/:id`, `/procurement/grn/:id` (invoice photo, live preview) |
| Chef availability | manual 86 now publishes `menu.item86` | `/menu/availability` |

## Integration fixes made by the planner

- `GET /products` caps `limit` at 100; the menu repository (a Phase 2 bug) and the availability screen asked for 200 and would get a 400. Both now page through the list.
- The edit-tab dialog always sent `linkType`, `tableId` and the limit. The server refuses `tableId` / `TABLE` on edit and rejects link changes on table tabs, and an unchanged limit re-ran the persona limit check and cleared the warning. Only changed fields are sent now.
- Closing a cash-deposit tab twice (for example after a declined card) applied the deposit twice. The deposit is now applied once.
- GRN post and stock count post claim the row (DRAFT → POSTED / SUBMITTED → POSTED) inside the transaction, so two simultaneous posts can't add stock twice.
- The socket client forces a new manager on every reconnect (the package caches managers per URL).
- Plan wording on the GRN example corrected: 14 cases received, 1 damaged written off, net +13.

Checks run (no toolchain in the sandbox): every relative TS/Dart import resolves; every Prisma model accessor and `where`/`data`/`include` key in the new code exists in the schema; every schema table, column and enum exists in the migrations; every frontend API call matches a backend route and method; every JSON key the Flutter models read is produced by the backend views; app constructors are called with existing named parameters; enum values exist.

## Before running

```bash
cd backend
npm install            # adds @nestjs/websockets, @nestjs/platform-socket.io, socket.io
npx prisma migrate deploy
npx prisma generate
npx prisma db seed     # demo stock, recipes, vendors, PO-0317
npm run build && npm test

cd ../frontend
flutter pub get        # adds socket_io_client
flutter analyze && flutter test
```

Nothing in Phase 3 has been compiled or run yet — expect a round of type fixes from `tsc` and `flutter analyze`, mostly around Prisma generated types and the socket packages.

## Pilot test script (exit test)

1. Sign in as Meera (bartender). Bar tabs → Open tab: Karthik R, age checked, Card pre-authorisation ••4821, held ₹5,000, limit ₹5,000, warn at 90%, Bar counter seat 3.
2. Add items → POS: 4 × Premium Lager, 6 × House Whisky 60 ml, Chicken Wings → Send. The BOT appears on `/kds?station=BAR` and the KOT on `/kds?station=KITCHEN` within 2 s.
3. Chef: Start → Bump. Waiter's `/service/ready` shows "Ready to serve" → Served.
4. The tab shows Near limit (₹4,700 / ₹5,000). Adding one more whisky shows "Tab T-07 has reached its ₹5,000 limit". Close & pay → 5% tip → UPI.
5. Inventory → House Whisky at Bar went down by 6 × 61.2 ml (60 ml + 2% allowance); lager by 4 bottles. Set Paneer to 0 by a count or wastage → Paneer Tikka shows Sold out on POS with no manual 86.
6. Storekeeper phone, airplane mode: Stock count · Bar, count a few items (banner "You're offline…"), reconnect, Submit. Manager posts. Inventory → Variance report: opening + received − sold − wastage = expected vs counted, unaccounted ml and ₹ per brand.
7. Procurement → Reorder suggestions → Send for approval (one PO per vendor). Manager approves and sends. Receive PO-0317 with an invoice photo: keg invoiced 5, received 4; lager 1 case damaged → preview says debit note ₹7,800 and ₹950 wastage; Post → Cellar stock up, PO shows Invoice mismatch, Debit notes lists DN-0001.

## Known gaps

- Card pre-auth is recorded only (last 4 digits + amount held); no gateway hold or release yet.
- Applying a cash deposit goes through normal payments, so the cash drawer opens again on Close & pay. Decide whether to skip the drawer for `TAB_DEPOSIT`.
- A `TAB_NO_SECURITY` approval is consumed before the tab is created, so a failed open uses it up.
- Tab numbers are count + 1 per business day; two tabs opened in the same instant can get the same number (no unique index).
- 86 is tenant-wide while stock is per outlet (multi-outlet tenants share the 86 flag).
- FIFO costing (weighted average is used), weight-based counting, OCR "Read from photo" on GRNs, keg/bottle empties and deposits, brand rebates.
- Vendor invoices, payables ageing and the 3-way match approval are Phase 5 (Accounting); only debit notes exist now.
- Opening stock entered on a new stock item has no cost, so it is valued at ₹0 until the first receipt.
- Earlier gaps still open: Phase 1b tenant scoping for older models, `@Roles` on routes without `@Can`, print jobs outside the order transaction.
