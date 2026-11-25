# P3-A report: data model, migration, stock core, permissions, seed (backend)

Status: code written, not compiled or run (no Node toolchain or database in the sandbox). Nothing committed.

## Files changed

Schema and migration
- `backend/prisma/schema.prisma`: new enums (StockUnit, CostingMethod, StockLocationKind, StockMovementType, WastageReason, StockCountStatus, PurchaseOrderStatus, GrnStatus, DebitNoteStatus, TabStatus, TabSecurity, TabLinkType, LockerStatus, LockerEventKind, KdsStatus); `ApprovalType.TAB_NO_SECURITY`; new models per PLAN 1.5; `Product.auto86`, `Product`/`ProductVariant`/`Order`/`DiningTable`/`Tenant`/`Outlet`/`User` back-relations; `ModifierOption.stockItemId/stockQty`; `Ticket` KDS columns and `@@index([outletId, kdsStatus])`.
- `backend/prisma/migrations/20261125160000_phase3_bar_stock/migration.sql` (new): enums, tables, indexes, FKs, `ALTER TYPE ApprovalType ADD VALUE`, new columns on products, modifier_options, tickets (with the `SERVED` backfill), `kds.bump` permission and persona rows, default locations per existing outlet.

Stock core (new)
- `backend/src/modules/stock-core/stock-core.module.ts`: `@Global()`, exports `StockLedgerService` and `DocumentNumberRepository`.
- `backend/src/modules/stock-core/stock-ledger.service.ts`: `post`, `deductForSentItems`, `reverseSale`, `salesLocationFor`, `onHand`.
- `backend/src/modules/stock-core/stock-ledger.repository.ts`: all Prisma access of the ledger.
- `backend/src/modules/stock-core/stock-math.ts`: `formatQty`, `weightedAverage`, `movementValue`, `recipeQty`, `toBase`, `nextDocNumber`, `varianceRow`.
- `backend/src/modules/stock-core/document-number.repository.ts`: `next(tx, tenantId, key)`.
- Specs: `stock-math.spec.ts`, `stock-ledger.service.spec.ts` (in-memory fake repository).
- `backend/src/modules/realtime/realtime.types.ts`: created with the exact PLAN 1.7 `RealtimeEvent` type. P3-C has already kept it unchanged.

Other
- `backend/src/common/tenancy/tenant-scope.extension.ts`: 14 tenant-owned Phase 3 models added to `TENANT_MODELS`.
- `backend/src/prisma/prisma.service.ts`: the same 14 models added to the loose-create list.
- `backend/src/common/permissions/catalog.ts`: `kds.bump` key, catalog row, grants for admin, manager, bartender, chef (EDIT), captain, waiter, cashier (VIEW).
- `frontend/lib/core/auth/permission_keys.dart`: `Perm.kdsBump`.
- `backend/src/app.module.ts`: imports and registers `StockCoreModule`, `RealtimeModule`, `InventoryModule`, `ProcurementModule`, `TabsModule`, `KdsModule`.
- `backend/prisma/seed.ts`: `seedStockDemo` (PLAN 1.8), called from `main()` after the POS demo.

## Decisions

- Quantities are `Prisma.Decimal` throughout. `recipeQty` and `toBase` round to 3 dp, `weightedAverage` to 6 dp, `movementValue` to 2 dp, all half-up.
- Weighted average: `H` is the total on hand over all of the tenant's locations, read before the receipt is written. Multiple receipts in one `post` call are applied in order, so each sees the average left by the previous one.
- Movement `unitCost`: receipts store the receipt cost; every other movement stores the current `avgCost`.
- Business date for movements: `businessDateFor(now, outlet timezone, '05:00')`, read from the outlet inside `post`.
- Auto-86: a recipe item with no level row counts as zero, so it triggers auto-86. Auto un-86 runs after RECEIPT, TRANSFER_IN and positive COUNT_ADJUST movements only, as PLAN 1.4 lists them.
- Sales location for a station: the active location listing the station, else the active `isDefaultSales` location, else no deduction (a warning is logged).
- `reverseSale` writes SALE_REVERSAL and WASTAGE per sale movement, then one `WastageEntry` (reason `VOID`) per WASTAGE movement, valued at that movement's unit cost. It needs a signed-in user (`WastageEntry.createdById` is required); a missing user throws `USER_REQUIRED`.
- Realtime events go into `MovementContext.events`. The caller emits them after commit.
- Document numbers: `DocumentCounter.value` is incremented by `next`, so the first number is 1. The seed sets `PO = 317`, so the next PO is `PO-0318`.

## Deviations and additions (beyond the plan text)

1. `StockTransfer` has `@@unique([tenantId, number])`, the same as PO, GRN and DN numbers.
2. Plain ids with no relation, to avoid unneeded foreign keys: `BarTab.approvalId`, `BottleLockerEntry.orderItemId`.
3. Every `*ById` user column in the new models has a relation to `User` (for example `StockMovement.createdBy`, `PurchaseOrder.approvedBy`). Where a model has two relations to `User`, the relations are named (`TabOpenedBy`/`TabClosedBy`, `PoCreatedBy`/`PoApprovedBy`, `GrnCreatedBy`/`GrnPostedBy`, `CountStartedBy`/`CountPostedBy`, `TicketCreatedBy`/`TicketBumpedBy`, `LockerEventBy`, `CountLineCountedBy`). `Ticket.createdBy` gained the name `TicketCreatedBy`; this changes Prisma naming only, not the SQL.
4. Low-stock notifications fire only for items with a par level above zero. An item with par 0 never raises the alert.
5. `kds.bump` takes sort order 6. The catalog and the migration shift the later permissions (menu.edit onwards) up by one, so `menu.edit` is now 7 and `admin.themes` is 16.
6. `DocumentCounter` (has a tenantId) is in `TENANT_MODELS`. The new models are also in the Prisma loose-create list.
7. `formatQty` puts the Unicode minus sign U+2212 in front of negative quantities. The frontend `formatStockQty` must use the same character.
8. `deductForSentItems` skips products with no `productId`. Order items without a product carry no recipe and no modifier stock in the current code path.
9. Seed values not given in PLAN.md (assumptions, please check):
   - Paneer Tikka is created in Bar bites at ₹320.00.
   - Items without a price in the plan (Soda, Sugar syrup, Fresh mint, Lime, Chicken wings, Paneer) have `avgCost` 0.
   - Opening quantities not in the plan: Dark Rum (Main store 12 btl), White Rum (Bar 6 btl par 6, Main store 12 btl), Soda (Bar 2000 ml), Sugar syrup (Bar 2 btl), Lime (Bar 40 pc), Stout (no opening).
   - Case sizes and last purchase rates: Single Malt case rate ₹37,440 (12 × ₹3,120); other spirit cases are 12 × the plan's bottle price.
   - Recipe wastage: 0% for the lager, the Mojito, wings, paneer and the bottle variant of House Whisky.
   - Modifier "With soda" draws 200 ml of soda.
   - Seed PO-0317 total ₹82,800 (₹38,000 lager, ₹31,200 keg, ₹13,600 stout).

## Requests for other workstreams

- P3-B: use `StockLedgerService.post` for every stock change and `DocumentNumberRepository.next` for numbers. Import `formatQty`, `varianceRow` and the other helpers from `stock-math.ts`. `StockCoreModule` is global, so `InventoryModule` and `ProcurementModule` need no imports for these providers.
- P3-C: `OrdersService` calls `deductForSentItems` and `reverseSale` inside the transaction and emits `ctx.events` after commit. Pass `station` for each item (the ticket station, which is the category station). The `Ticket` KDS columns exist as named in PLAN 1.5 (`kdsStatus`, `startedAt`, `readyAt`, `servedAt`, `recalledAt`, `bumpedById`, `overdueAlertedAt`).
- P3-C: `app.module.ts` imports `./modules/realtime/realtime.module`, `./modules/tabs/tabs.module`, `./modules/kds/kds.module`, `./modules/inventory/inventory.module` and `./modules/procurement/procurement.module`. These files must exist with those class names.
- P3-E: `formatStockQty` must match `formatQty` exactly, including the U+2212 sign and the "0 ml" case.
- Integration: `PERMISSION_CATALOG` and `DEFAULT_PERSONAS` now include `kds.bump`. Re-running the seed adds the new grant rows to existing personas, because persona matrix rows are upserted.

## What is untested

- Nothing has been compiled. `prisma generate`, `tsc` and `jest` have not been run.
- The migration has not been applied to any database. I checked by script that every new schema model and column appears in the migration and that every relation has both sides. The ALTER statements and the `ApprovalType` enum addition are checked by reading only.
- `@@unique([productId, variantId])` on `Recipe` has an optional field. Prisma should accept it, but this has not been verified.
- The ledger specs use an in-memory fake repository, so they check the service logic only, not the SQL or the tenant extension.
- The seed has not been run. Its upserts and the `DocumentCounter` reset rule need a database run.
- `formatQty` for packSize equal to 1 with a non-integer quantity, and for unusual pack names, is covered only by the listed cases.

## Memory

No stored memory was used for this task.
