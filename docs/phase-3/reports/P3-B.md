# P3-B report: inventory and procurement APIs

Scope: PLAN.md 1.7 (inventory and procurement tables and GRN post rules), 1.6 (permissions), and the P3-B spec. No commits, no branch changes, no git. Nothing was compiled or run (no Node toolchain or network in this environment), so every file was checked by reading only.

## Files

New, under `backend/src/modules/inventory/`:
- `inventory.module.ts`, `inventory.repository.ts`, `access.ts`, `decimal-input.ts`, `ledger-context.ts`, `inventory-views.ts`, `inventory-math.ts`
- `stock-items.service.ts`, `stock-items.controller.ts` (locations, items, par, movements)
- `transfers.service.ts`
- `counts.service.ts`, `stock-ops.controller.ts` (transfers, counts, wastage, uploads)
- `wastage.service.ts`, `stock-uploads.service.ts`
- `variance.service.ts`, `variance.controller.ts` (`/stock/variance`, `/stock/kegs`, `/inventory/summary`)
- `recipes.service.ts`, `recipes.controller.ts`
- `dto/inventory.dto.ts`, `dto/recipes.dto.ts`
- Specs: `inventory-math.spec.ts`, `counts.service.spec.ts`, `wastage.service.spec.ts`, `variance.service.spec.ts`

New, under `backend/src/modules/procurement/`:
- `procurement.module.ts`, `procurement.repository.ts`, `procurement-math.ts`, `procurement-views.ts`
- `vendors.service.ts`, `vendors.controller.ts`
- `purchase-orders.service.ts`, `purchase-orders.controller.ts`
- `grns.service.ts`, `grns.controller.ts` (GrnsController and DebitNotesController)
- `debit-notes.service.ts`
- `dto/procurement.dto.ts`
- Specs: `procurement-math.spec.ts`, `grns.service.spec.ts`, `purchase-orders.service.spec.ts`

Edited, under `backend/src/modules/modifiers/`:
- `dto/modifier-group.dto.ts`: `stockItemId` and `stockQty` on ModifierOptionDto
- `modifiers.repository.ts`: `stockItemsByIds(ids)`
- `modifiers.service.ts`: list and create/update return views; stock references validated (INVALID_REFERENCE); stockQty stored with dp 3, min 0.001

Edited: `docs/API.md` (sections "Inventory (Phase 3)" and "Procurement (Phase 3)", before "Error envelope").

## Decisions

- Money and stock are `Prisma.Decimal` throughout. JSON inputs accept a number or a numeric string. Outputs are 3dp strings for quantities and 2dp for money, with a 6dp unit cost. `fullKegs` is an integer. Dates are YYYY-MM-DD.
- `GET /stock/wastage` returns `{ items, totalValue }`.
- Count statuses OPEN and SUBMITTED both block a new count at the same location. An OPEN count shows live onHand as expectedQty until it is submitted; submit snapshots expectedQty. Post writes COUNT_ADJUST = counted − expected, skipping zero adjustments and uncounted lines.
- Wastage over 2000 needs a photo (PHOTO_REQUIRED) and notifies the `stock.purchaseOrders` permission holders. VOID and DAMAGED_DELIVERY are refused as manual reasons.
- Item list status filter matches any flag. Without a locationId, levels are summed across locations, and belowPar is evaluated per location.
- Expiry flag: GRN lines expiring within [today, today+7] for items with stock > 0. Already-expired lines are not flagged.
- Variance and summary default to the last 7 business days. Liquor defaults to true. Access is `stock.count` VIEW or `reports.view` LIMITED, checked in the service.
- Pour cost: cost of liquor SALE movements divided by revenue (lineTotal minus taxAmount of non-voided items of liquor-recipe products over the window). Shown as a 1dp percent string. Revenue is an approximation.
- `onTapMl` = BAR-kind location onHand modulo packSize. There is no tap-state model.
- `belowParCount` counts item-location pairs below par.
- Recipes: GET is `@Can stock.count VIEW` plus a `menu.edit` VIEW check in the service. PUT is `@Can menu.edit EDIT`. Each recipe is replaced in one transaction. A null recipe is always present in the views.
- GRN mismatch compares invoiced against ordered only for PO-linked lines, and invoice value versus the invoiced sum within a tolerance of 1. Invoice value is stored as entered, or defaulted, and recomputed on each update.
- GRN post: RECEIPT per line at rate ÷ purchaseUnitQty (GRN_LINE ref), with the item's last purchase rate updated. Damaged goods become a WastageEntry (DAMAGED_DELIVERY) and a WASTAGE movement. Short lines create a debit note (DN). PO line receivedQty is incremented and the PO status is recomputed. Posting is refused without an invoice number, and without a transport permit for liquor.
- PO send from DRAFT or PENDING_APPROVAL auto-approves. `approve`, `send` and `cancel` require `stock.purchaseOrders` APPROVE. Cancel is refused once any receivedQty > 0 or the PO is RECEIVED. Reorder requests create one PENDING_APPROVAL PO per vendor, and refuse items with no vendor (VENDOR_MISSING).
- Notifications use the permission key `stock.purchaseOrders`, not per-user APPROVE holders.
- Upload validation uses magic bytes (jpg, png, pdf), 8 MB limit, stored via `STORAGE_SERVICE.save(buffer, name, 'stock')`.

## Deviations and inconsistencies in the plan

- PLAN.md 1.7 says "Stout 4 cs → stock +14 cases (13 good + 1 written off)". The same example also lists lager 10 and stout 4 cases received, so 14 received and 1 damaged gives net +13 cases. I implemented the consistent reading: received 14, damaged 1, net +13 cases, keg +4, debit note 7800, wastage 950, payable 59,100. The plan text should be corrected.
- Opening stock on item create has no cost input, so the opening value is 0 until a receipt. Reported as a gap.

## Assumptions about other workstreams

I assumed these Prisma models and fields exist (P3-A owns the schema):
- StockItem: preferredVendorId, lastPurchaseRate, isLiquor, isKeg, purchaseUnitQty, packSize, packName, purchaseUnitName, costingMethod, shelfLifeDays, sku, categoryName, avgCost
- StockLocation: kind, stations, isDefaultSales, sortOrder, isActive
- StockLevel: compound key locationId_stockItemId, parLevel
- Recipe with a `lines` relation (nested create)
- ModifierOption: stockItemId, stockQty
- WastageEntry fields as used in the repositories; GoodsReceiptLine.expiry
- Vendor, PurchaseOrder, GoodsReceipt, DebitNote, DocumentCounter
- Prisma enum types imported from `@prisma/client`

Stock-core and realtime APIs used as they exist: `StockLedgerService.post/onHand`, `MovementContext`, `formatQty`, `toBase`, `nextDocNumber`, `varianceRow`, `DocumentNumberRepository.next`, `RealtimeService.publish`.

## Requests to other workstreams

1. P3-A: confirm the ModifierOption `stockItem` relation name and the Recipe `lines` relation name.
2. P3-A: confirm `formatQty` and `varianceRow` input types (Decimal inputs, counted nullable).
3. P3-A: confirm that `StockCoreModule` and `RealtimeModule` are global, and that app.module registers InventoryModule and ProcurementModule.
4. P3-C: confirm the RealtimeEvent field names used by `publishLedgerEvents` (`ledger-context.ts`).
5. P3-A: confirm the Prisma model and enum names listed above.
6. Plan owner: correct the Stout example in PLAN.md 1.7 as described above.

## Verification status

Untested. Nothing was compiled, type-checked, linted or run. Checks done by reading:
- Unused imports were scanned across all P3-B files; one unused import (`ZERO` in transfers.service.ts) was removed.
- Every `this.repo.<method>` call in the inventory, procurement and modifiers services was checked against the repository definitions. None are missing.
- Helper signatures used (`dayWindow`, `addDays`, `businessDateFor`, `toDateOnly`, `nextDocNumber`, `toBase`, `dateInput`, `RealtimeService.publish`) were checked against their definitions.
- Earlier passes fixed: a cast in upsertCountLine, the stock-items search filter (now typed as `Prisma.StockItemWhereInput` with `Prisma.QueryMode.insensitive`), a nonexistent `CountCreateDataFn` import, and several stray exports and junk code.

Not yet re-read line by line in this pass: `purchase-orders.service.ts`, `variance.service.ts`, `recipes.service.ts`, `wastage.service.ts`, the controllers, the DTOs and the specs. These need a `tsc --noEmit` and `jest` run before merge.
