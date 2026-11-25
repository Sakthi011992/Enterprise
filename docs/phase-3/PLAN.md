# Phase 3 — Bar operations, KDS and stock: detailed implementation plan

Branch: `phase-1-foundation` (Phase 3 lands in the same PR #2). Builds on Phase 1 (`docs/phase-1/PLAN.md`) and Phase 2 (`docs/phase-2/PLAN.md`, `docs/phase-2/INTEGRATION.md`).

Design boards (`docs/ui-design/project/`): BarTabs, MobileTab, KDS, Inventory, Procurement, GRN, MobileStock, MobileStaff (wastage, reorder request, waiter ready alerts), TabletOps (receiving with invoice photo, chef 86 & wastage), MenuEditors (recipe section), Flow-bartender, Flow-chef, Flow-storekeeper. Read the text of a board with `python3 -I /home/claude/scripts/txt.py <Board>.dc.html` from that folder.

**Exit test (pilot gate):**
1. Bartender Meera opens tab T-07 for Karthik (age checked, card ••4821 pre-auth ₹5,000 held, limit ₹5,000, warn at 90%), links it to Bar seat 3, adds 4 lagers + 6 × House Whisky 60 ml + wings → BOT appears on the **Bar KDS** and KOT on the **Kitchen KDS** within 2 s (WebSocket; 5 s polling if the socket is down) → chef taps Start, then Bump → waiter gets "Ready to serve" → Served. Tab shows "Near limit" at ₹4,700 / ₹5,000 → adding another whisky is refused with `TAB_LIMIT_REACHED` → Close & pay with a 5% tip by UPI.
2. Each 60 ml whisky deducted 60 ml (+ wastage allowance) of House Whisky from the **Bar** location; the lager recipe deducted one 650 ml bottle; when Paneer stock reaches zero, Paneer Tikka is auto-86'd on POS.
3. Storekeeper counts the bar on an Android phone **offline**, syncs, the manager posts the count → **liquor variance report** for the week shows per brand: opening + received − sold − wastage = expected vs counted → unaccounted ml and ₹.
4. Storekeeper requests a reorder from "Below par" → draft PO per vendor → manager approves and sends → delivery is received against the PO with an invoice photo (one keg invoiced but not received → debit note ₹7,800; one damaged case → wastage ₹950) → stock goes up in the Cellar and the weighted average cost updates.

---

## 0. Ground rules (same as Phases 1–2)

1. Edit only the files your workstream owns (section 2). Anything you need from another workstream goes in your report under "Requests".
2. No network, no Node/Flutter toolchain in the sandbox: write code that would compile; reread every file you write; check every import path exists (or is created by a workstream named in this plan).
3. Contracts in section 1 are exact: names, paths, JSON keys, HTTP methods, error codes. Do not rename.
4. Backend: **controller → service → repository**; only repositories touch Prisma (`.claude/skills/common-backend.md`). Use `@Can(key, min)` (`common/decorators/can.decorator.ts`), `@CurrentUser() auth: AuthUser` (`common/decorators/current-user.decorator.ts`; has `tenantId`, `outletId`, `userId`, `permissions`), `apiError(status, code, message, details?)` (`common/filters/api-error.ts`), `PermissionsService.check / assertWithinLimit` (`modules/personas/permissions.service.ts`). Money is `Prisma.Decimal` with `round2` (`common/utils/money.util.ts`); stock quantities are `Prisma.Decimal` with 3 decimals; unit costs 6 decimals. Never JS floats for money or stock. Mutations in a Prisma transaction (`repo.transaction(async (tx) => …)`, see `orders.repository.ts`).
5. Frontend: kit from `core/ui/ui.dart`, colours from `context.tokens` / `context.ext`, session from `core/auth/*` (`can`, `Perm`, `AccessLevel`, `sessionProvider`, `ApiError`), HTTP via `dioProvider`, Riverpod providers like Phase 2 (`features/pos/data/pos_repository.dart` is the reference). Layouts are responsive: the same screen serves desktop, tablet and phone (`LayoutBuilder`, breakpoints 600 / 1024). Ops screens used on tablets/phones use `DensityScope(pos)` (52 px touch targets).
6. Business date: `businessDateFor(now, tz, '05:00')` from `backend/src/common/pricing/business-date.ts`; day window from `backend/src/modules/orders/business-day-window.ts` (`dayWindow`).
7. Don't commit. Write `docs/phase-3/reports/P3-<letter>.md` at the end: files changed, decisions, deviations, requests, what's untested.

---

## 1. Shared contracts

### 1.1 Stock units and quantities

- Every stock item has a **base unit**: `ML` (liquids), `G` (weighed food), `PC` (pieces: limes, eggs, glasses). All stock quantities everywhere (levels, movements, recipes, counts, wastage) are in the base unit.
- `packSize` = base units in one bottle/pack/keg (750 for a 750 ml bottle, 30000 for a 30 L keg, 1 for PC). `packName` = "btl", "keg", "pc", "kg pack".
- `purchaseUnitName` = "Case of 12 bottles"; `purchaseUnitQty` = base units in one purchase unit (12 × 750 = 9000). POs and GRNs are in purchase units; posting converts to base units.
- Display rule (backend helper `formatQty`, frontend `formatStockQty`, identical output): `packSize > 1` → `"<floor(q / packSize)> <packName> + <q mod packSize> <unit lower-case>"`, dropping a zero part (`"8 btl + 410 ml"`, `"3 btl"`, `"410 ml"`, `"0 ml"`); `packSize == 1` → `"<q> <unit lower-case>"` with up to 3 decimals trimmed (`"1.2 kg"` is **not** produced — G shows `"1200 g"`). Negative quantities show a leading `−` on the whole string.
- Counting input on phones: bottles + "ml open" → `bottles × packSize + openMl`.

### 1.2 Costing (weighted average)

- `StockItem.avgCost` = ₹ per base unit, `Decimal(14,6)`, tenant-wide.
- On a **receipt** of `q` base units at unit cost `c` (= GRN line rate ÷ `purchaseUnitQty`): with `H` = total on hand for the item across all locations of the tenant **before** the receipt: if `H <= 0` → `avgCost = c`; else `avgCost = (H × avgCost + q × c) / (H + q)`, rounded to 6 dp.
- Every movement row stores `unitCost` = `avgCost` at the time (receipts store `c`). Value of a movement = `qty × unitCost` rounded to 2 dp.
- `costingMethod` `FIFO` is stored and shown but computed as weighted average in Phase 3 (known gap, say so in the item editor helper text: "FIFO costing arrives later; weighted average is used for now").

### 1.3 Stock ledger

Every change to stock is a `StockMovement` row and updates the matching `StockLevel.onHand` in the same transaction. Signed `qty` (positive = into the location).

| type | sign | created by |
|---|---|---|
| `OPENING` | ± | stock item create with opening qty, seed |
| `RECEIPT` | + | GRN post (received qty, damaged included) |
| `SALE` | − | order lines sent (KOT/BOT) — recipe deduction |
| `SALE_REVERSAL` | + | void of a **sent** line (paired with a `WASTAGE` of the same qty, reason `VOID`) |
| `WASTAGE` | − | wastage log, GRN damaged qty, voided sent lines |
| `TRANSFER_OUT` / `TRANSFER_IN` | − / + | stock transfer (pair, same `refId`) |
| `COUNT_ADJUST` | ± | stock count post: `counted − expectedAtSubmit` |

Stock may go negative (pubs pour before deliveries are entered); negative levels show a red "Negative" status.

**Variance formula** (per stock item and location, business dates `from..to` inclusive; `opening` = sum of all movements with `businessDate < from`):

```
received     = Σ RECEIPT
transfersIn  = Σ TRANSFER_IN
transfersOut = −Σ TRANSFER_OUT
sold         = −Σ (SALE + SALE_REVERSAL)
wastage      = −Σ WASTAGE
expected     = opening + received + transfersIn − transfersOut − sold − wastage
countAdjust  = Σ COUNT_ADJUST
counted      = expected + countAdjust   (null when no count was posted in the range)
variance     = countAdjust               (negative = unaccounted loss)
varianceValue= Σ (COUNT_ADJUST qty × unitCost)
```

### 1.4 Recipe deduction on send

When `OrdersService.send` turns lines from `NEW` to `SENT`, for each line in the same transaction:
1. Recipe = the recipe for `(productId, variantId)`; if none, the recipe for `(productId, null)`; if none, no deduction.
2. For each recipe line: `qty = line.qty × (1 + wastagePercent / 100) × orderItem.quantity` (3 dp).
3. Plus, for each modifier on the line (the JSON `modifiers` array has `optionId`) whose `ModifierOption.stockItemId` is set: `stockQty × orderItem.quantity`.
4. Location = the outlet's `StockLocation` whose `stations` array contains the ticket station of the line (Category.station); else the outlet's location with `isDefaultSales = true`; if none, skip deduction and log a warning.
5. Movement `SALE`, `refType: 'ORDER_ITEM'`, `refId: orderItem.id`, `unitCost = avgCost`.
6. **Auto-86** (after all deductions of the send): for each product whose recipe (any variant) uses a stock item whose level at that location is now `<= 0`, set `Product.is86 = true, auto86 = true` and emit realtime `menu.item86` (`{ productId, name, is86: true, auto: true }`). **Auto un-86**: when a receipt, transfer-in or count makes every recipe item of an `auto86` product `> 0` at the sales location, set `is86 = false, auto86 = false` and emit `menu.item86` with `is86: false`. Manual 86 (`auto86 = false`) is never undone automatically.
7. **Low stock**: when a level crosses below `parLevel` (was ≥ par, now < par), create one `Notification` (`type: 'stock'`, `permissionKey: 'stock.purchaseOrders'`, title `"<item> is below par at <location>"`) and emit `stock.low`.

Voids of SENT lines (`voidItems`, `voidOrder`): for each SALE movement with `refId = orderItem.id`, write `SALE_REVERSAL` (+qty) and `WASTAGE` (−qty, `WastageEntry` reason `VOID`, note = void reason). Voids of NEW lines do nothing.

### 1.5 Data model (owned by P3-A) — add to `schema.prisma`

All new tenant-owned models get `tenantId` + relation to `Tenant`, and are added to `TENANT_MODELS` in `backend/src/common/tenancy/tenant-scope.extension.ts` (models without `tenantId` — lines/levels/events — are not). Add back-relations on `Tenant`, `Outlet`, `User`, `Product`, `ProductVariant`, `Order`, `ModifierOption` as Prisma requires.

```prisma
enum StockUnit { ML G PC }
enum CostingMethod { WEIGHTED_AVERAGE FIFO }
enum StockLocationKind { STORE BAR KITCHEN CELLAR }
enum StockMovementType { OPENING RECEIPT SALE SALE_REVERSAL WASTAGE TRANSFER_OUT TRANSFER_IN COUNT_ADJUST }
enum WastageReason { BROKEN SPILLED EXPIRED COMP STAFF_MEAL BURNT DROPPED RETURNED DAMAGED_DELIVERY VOID OTHER }
enum StockCountStatus { OPEN SUBMITTED POSTED CANCELLED }
enum PurchaseOrderStatus { DRAFT PENDING_APPROVAL APPROVED SENT PARTLY_RECEIVED RECEIVED INVOICE_MISMATCH CANCELLED }
enum GrnStatus { DRAFT POSTED }
enum DebitNoteStatus { OPEN SETTLED CANCELLED }
enum TabStatus { OPEN CLOSED VOID }
enum TabSecurity { CARD_PREAUTH CASH_DEPOSIT HOUSE_ACCOUNT NONE }
enum TabLinkType { BAR_SEAT TABLE QUEUE_TOKEN NONE }
enum LockerStatus { ACTIVE FINISHED EXPIRED REMOVED }
enum LockerEventKind { STORE SERVE ADJUST REMOVE }
enum KdsStatus { NEW PREPARING READY SERVED }
// extend existing enum ApprovalType with: TAB_NO_SECURITY

model StockItem {
  id               String        @id @default(uuid())
  tenantId         String
  name             String        // "Single Malt 12Y 750 ml"
  sku              String?
  categoryName     String?       // free text group: "Spirits", "Beer", "Produce"
  baseUnit         StockUnit     @default(ML)
  packSize         Decimal       @db.Decimal(14, 3) @default(1)
  packName         String        @default("pc")
  purchaseUnitName String        @default("Unit")
  purchaseUnitQty  Decimal       @db.Decimal(14, 3) @default(1)
  costingMethod    CostingMethod @default(WEIGHTED_AVERAGE)
  avgCost          Decimal       @db.Decimal(14, 6) @default(0)  // ₹ per base unit
  lastPurchaseRate Decimal?      @db.Decimal(12, 2)               // ₹ per purchase unit
  preferredVendorId String?
  isLiquor         Boolean       @default(false)
  isKeg            Boolean       @default(false)
  shelfLifeDays    Int?
  isActive         Boolean       @default(true)
  createdAt        DateTime      @default(now())
  updatedAt        DateTime      @updatedAt
  // relations: tenant, preferredVendor (Vendor?, SetNull), levels, movements, recipeLines, modifierOptions,
  //            countLines, wastage, transferLines, poLines, grnLines, lockerEntries
  @@unique([tenantId, name])
  @@index([tenantId])
  @@map("stock_items")
}

model StockLocation {
  id             String            @id @default(uuid())
  tenantId       String
  outletId       String
  name           String            // "Main store", "Bar", "Kitchen", "Cellar"
  kind           StockLocationKind
  stations       String[]          @default([])   // Category.station values that sell from here: ["BAR"]
  isDefaultSales Boolean           @default(false) // fallback for stations not listed anywhere
  isActive       Boolean           @default(true)
  sortOrder      Int               @default(0)
  @@unique([outletId, name])
  @@index([outletId])
  @@map("stock_locations")
}

model StockLevel {
  locationId  String
  stockItemId String
  onHand      Decimal  @db.Decimal(14, 3) @default(0)
  parLevel    Decimal  @db.Decimal(14, 3) @default(0)
  updatedAt   DateTime @updatedAt
  @@id([locationId, stockItemId])
  @@map("stock_levels")
}

model StockMovement {
  id           String            @id @default(uuid())
  tenantId     String
  outletId     String
  locationId   String
  stockItemId  String
  type         StockMovementType
  qty          Decimal           @db.Decimal(14, 3)   // signed, base units
  unitCost     Decimal           @db.Decimal(14, 6)
  refType      String?           // ORDER_ITEM | GRN_LINE | TRANSFER | COUNT | WASTAGE | ITEM
  refId        String?
  businessDate DateTime          @db.Date
  note         String?
  createdById  String?
  createdAt    DateTime          @default(now())
  @@index([locationId, stockItemId, businessDate])
  @@index([refType, refId])
  @@index([outletId, businessDate])
  @@map("stock_movements")
}

model Recipe {
  id        String   @id @default(uuid())
  tenantId  String
  productId String           // Product, Cascade
  variantId String?          // ProductVariant, Cascade; null = all variants without their own recipe
  note      String?
  updatedAt DateTime @updatedAt
  lines     RecipeLine[]
  @@unique([productId, variantId])
  @@map("recipes")
}

model RecipeLine {
  id             String  @id @default(uuid())
  recipeId       String  // Cascade
  stockItemId    String  // Restrict
  qty            Decimal @db.Decimal(14, 3)   // base units per serving
  wastagePercent Decimal @db.Decimal(5, 2) @default(0)
  sortOrder      Int     @default(0)
  @@index([recipeId])
  @@map("recipe_lines")
}

// ModifierOption gets two new nullable columns:
//   stockItemId String?  (StockItem, SetNull)    stockQty Decimal? @db.Decimal(14, 3)
// Product gets: auto86 Boolean @default(false)
// Ticket gets: kdsStatus KdsStatus @default(NEW), startedAt DateTime?, readyAt DateTime?, servedAt DateTime?,
//              recalledAt DateTime?, bumpedById String? (User, SetNull), overdueAlertedAt DateTime?
//              + @@index([outletId, kdsStatus])

model StockTransfer {
  id             String   @id @default(uuid())
  tenantId       String
  outletId       String
  number         String   // "TR-0012" per tenant
  fromLocationId String
  toLocationId   String
  note           String?
  createdById    String
  createdAt      DateTime @default(now())
  lines          StockTransferLine[]
  @@index([outletId, createdAt])
  @@map("stock_transfers")
}

model StockTransferLine {
  id          String  @id @default(uuid())
  transferId  String  // Cascade
  stockItemId String
  qty         Decimal @db.Decimal(14, 3)
  @@map("stock_transfer_lines")
}

model StockCount {
  id           String           @id @default(uuid())
  tenantId     String
  outletId     String
  locationId   String
  status       StockCountStatus @default(OPEN)
  businessDate DateTime         @db.Date
  startedById  String
  submittedAt  DateTime?
  postedAt     DateTime?
  postedById   String?
  note         String?
  createdAt    DateTime         @default(now())
  lines        StockCountLine[]
  @@index([outletId, status])
  @@map("stock_counts")
}

model StockCountLine {
  id               String    @id @default(uuid())
  countId          String    // Cascade
  stockItemId      String
  countedQty       Decimal?  @db.Decimal(14, 3)  // null = not counted
  expectedQty      Decimal?  @db.Decimal(14, 3)  // onHand snapshot at submit
  note             String?
  confirmedOutlier Boolean   @default(false)     // "Count is correct" tapped on a >30% difference
  countedAt        DateTime?
  countedById      String?
  @@unique([countId, stockItemId])
  @@map("stock_count_lines")
}

model WastageEntry {
  id          String        @id @default(uuid())
  tenantId    String
  outletId    String
  locationId  String
  stockItemId String
  qty         Decimal       @db.Decimal(14, 3)   // positive, base units
  value       Decimal       @db.Decimal(12, 2)
  reason      WastageReason
  note        String?
  photoUrl    String?
  refType     String?       // ORDER_ITEM | GRN_LINE | null
  refId       String?
  businessDate DateTime     @db.Date
  createdById String
  createdAt   DateTime      @default(now())
  @@index([outletId, businessDate])
  @@map("wastage_entries")
}

model Vendor {
  id               String   @id @default(uuid())
  tenantId         String
  name             String   // "Metro Spirits Distributors"
  contactName      String?
  phone            String?
  email            String?
  gstin            String?
  address          String?
  paymentTermsDays Int      @default(30)
  isActive         Boolean  @default(true)
  createdAt        DateTime @default(now())
  updatedAt        DateTime @updatedAt
  @@unique([tenantId, name])
  @@map("vendors")
}

model PurchaseOrder {
  id                String              @id @default(uuid())
  tenantId          String
  outletId          String
  number            String              // "PO-0318" per tenant
  vendorId          String
  locationId        String              // deliver to
  status            PurchaseOrderStatus @default(DRAFT)
  dueDate           DateTime?           @db.Date
  transportPermitNo String?
  total             Decimal             @db.Decimal(12, 2) @default(0)
  note              String?
  createdById       String
  submittedAt       DateTime?
  approvedById      String?
  approvedAt        DateTime?
  sentAt            DateTime?
  createdAt         DateTime            @default(now())
  updatedAt         DateTime            @updatedAt
  lines             PurchaseOrderLine[]
  @@unique([tenantId, number])
  @@index([outletId, status])
  @@map("purchase_orders")
}

model PurchaseOrderLine {
  id          String  @id @default(uuid())
  poId        String  // Cascade
  stockItemId String
  qty         Decimal @db.Decimal(12, 3)   // purchase units
  rate        Decimal @db.Decimal(12, 2)   // ₹ per purchase unit
  total       Decimal @db.Decimal(12, 2)
  receivedQty Decimal @db.Decimal(12, 3) @default(0)   // purchase units, sum of posted GRNs
  sortOrder   Int     @default(0)
  @@map("purchase_order_lines")
}

model GoodsReceipt {
  id                String    @id @default(uuid())
  tenantId          String
  outletId          String
  number            String    // "GRN-0091" per tenant
  poId              String?
  vendorId          String
  locationId        String    // "Into"
  status            GrnStatus @default(DRAFT)
  vendorInvoiceNo   String?
  invoiceDate       DateTime? @db.Date
  receivedOn        DateTime  @db.Date
  transportPermitNo String?
  invoicePhotoUrl   String?
  poValue           Decimal   @db.Decimal(12, 2) @default(0)
  invoiceValue      Decimal   @db.Decimal(12, 2) @default(0)
  receivedValue     Decimal   @db.Decimal(12, 2) @default(0)
  debitNoteAmount   Decimal   @db.Decimal(12, 2) @default(0)
  damagedValue      Decimal   @db.Decimal(12, 2) @default(0)
  payable           Decimal   @db.Decimal(12, 2) @default(0)
  mismatch          Boolean   @default(false)
  createdById       String
  postedById        String?
  postedAt          DateTime?
  createdAt         DateTime  @default(now())
  lines             GoodsReceiptLine[]
  @@unique([tenantId, number])
  @@index([outletId, createdAt])
  @@map("goods_receipts")
}

model GoodsReceiptLine {
  id          String    @id @default(uuid())
  grnId       String    // Cascade
  poLineId    String?
  stockItemId String
  orderedQty  Decimal   @db.Decimal(12, 3) @default(0)   // purchase units
  invoicedQty Decimal   @db.Decimal(12, 3) @default(0)
  receivedQty Decimal   @db.Decimal(12, 3) @default(0)   // includes damaged
  damagedQty  Decimal   @db.Decimal(12, 3) @default(0)
  rate        Decimal   @db.Decimal(12, 2)               // ₹ per purchase unit (invoice rate)
  batch       String?
  expiry      DateTime? @db.Date
  @@map("goods_receipt_lines")
}

model DebitNote {
  id        String          @id @default(uuid())
  tenantId  String
  outletId  String
  number    String          // "DN-0007" per tenant
  vendorId  String
  grnId     String?
  amount    Decimal         @db.Decimal(12, 2)
  reason    String          // "1 × Wheat beer keg 30 L invoiced, not received"
  status    DebitNoteStatus @default(OPEN)
  createdAt DateTime        @default(now())
  @@unique([tenantId, number])
  @@map("debit_notes")
}

model DocumentCounter {     // per-tenant document numbers: PO, GRN, DN, TR
  tenantId String
  key      String  // "PO" | "GRN" | "DN" | "TR"
  value    Int     @default(0)
  @@id([tenantId, key])
  @@map("document_counters")
}

model BarTab {
  id             String      @id @default(uuid())
  tenantId       String
  outletId       String
  number         String      // "T-07": per outlet per business day, 2 digits min
  businessDate   DateTime    @db.Date
  orderId        String      @unique   // the tab's BAR_COUNTER order
  guestName      String
  mobile         String?
  ageChecked     Boolean
  security       TabSecurity
  cardLast4      String?     // CARD_PREAUTH
  amountHeld     Decimal     @db.Decimal(12, 2) @default(0)  // pre-auth hold or cash deposit
  houseAccount   String?     // HOUSE_ACCOUNT: "Corporate: Acme"
  tabLimit       Decimal     @db.Decimal(12, 2)
  warnAtPercent  Int         @default(80)   // 80 | 90
  warnedAt       DateTime?   // set once when spent crosses warnAt
  linkType       TabLinkType @default(NONE)
  linkLabel      String?     // "Bar seat 3", "Queue W-009", "VIP 2"
  tableId        String?     // when linkType TABLE
  status         TabStatus   @default(OPEN)
  approvalId     String?     // TAB_NO_SECURITY approval
  openedById     String
  openedAt       DateTime    @default(now())
  closedAt       DateTime?
  closedById     String?
  @@index([outletId, status])
  @@map("bar_tabs")
}

model BottleLockerEntry {
  id           String       @id @default(uuid())
  tenantId     String
  outletId     String
  guestName    String
  mobile       String?
  cardLast4    String?      // shown as "Vikram S · ••7720"
  stockItemId  String?
  bottleName   String       // snapshot "Single Malt 12Y 750 ml"
  bottleMl     Int          // 750
  remainingMl  Int
  storedAt     DateTime     @default(now())
  expiresAt    DateTime     @db.Date
  status       LockerStatus @default(ACTIVE)
  orderItemId  String?      // the bottle sale, when known
  note         String?
  createdById  String
  events       BottleLockerEvent[]
  @@index([outletId, status])
  @@map("bottle_locker_entries")
}

model BottleLockerEvent {
  id        String          @id @default(uuid())
  entryId   String          // Cascade
  kind      LockerEventKind
  ml        Int             // served or adjusted ml (signed for ADJUST)
  byId      String
  note      String?
  createdAt DateTime        @default(now())
  @@map("bottle_locker_events")
}
```

**Migration** `backend/prisma/migrations/20261125160000_phase3_bar_stock/migration.sql`, hand-written in the style of the Phase 2 migration: new enums, tables, indexes, FKs; `ALTER TYPE "ApprovalType" ADD VALUE 'TAB_NO_SECURITY';` (not used elsewhere in the migration); new columns on `products`, `modifier_options`, `tickets` (`"kdsStatus" "KdsStatus" NOT NULL DEFAULT 'NEW'`; then `UPDATE "tickets" SET "kdsStatus" = 'SERVED' WHERE "createdAt" < now()` so old Phase 2 tickets don't flood the KDS); insert the new permission `kds.bump` (see 1.6) into `permissions` and `persona_permissions` for every existing persona row by persona key; for every existing outlet insert locations `Main store` (STORE, sortOrder 0), `Bar` (BAR, stations `{BAR}`, sortOrder 1), `Kitchen` (KITCHEN, stations `{KITCHEN,TANDOOR,GRILL}`, isDefaultSales true, sortOrder 2), `Cellar` (CELLAR, sortOrder 3).

### 1.6 Permissions

New catalog key **`kds.bump`** — group "Sales", label "Kitchen display (start, bump, recall)", no limit unit, sortOrder right after `sales.tab.open`. Default matrix: admin EDIT, manager EDIT, bartender EDIT, chef EDIT, captain VIEW, waiter VIEW, cashier VIEW, storekeeper NONE, kiosk NONE. Add to `PermissionKey`, `PERMISSIONS`, every persona matrix in `backend/src/common/permissions/catalog.ts`, and to `Perm.kdsBump = 'kds.bump'` in `frontend/lib/core/auth/permission_keys.dart`.

| Action | Rule |
|---|---|
| Bar tabs list / view | `sales.tab.open` VIEW |
| Open tab | `sales.tab.open` LIMITED: `assertWithinLimit(auth, 'sales.tab.open', tabLimit)`; security `NONE` additionally needs `sales.tab.open` APPROVE **or** an `approvalId` of type `TAB_NO_SECURITY` (payload `{ guestName, tabLimit }`) |
| Raise a tab limit | same limit rule on the new limit |
| Bottle locker | `sales.tab.open` LIMITED (view: VIEW) |
| KDS view | `kds.bump` VIEW |
| KDS start/bump/recall | `kds.bump` EDIT |
| Mark served (ready list) | `sales.orders.take` EDIT or `kds.bump` EDIT |
| 86 toggle (manual) | `menu.mark86` EDIT (exists, Phase 2) |
| Stock items, locations, recipes — view | `stock.count` VIEW (recipes: also `menu.edit` VIEW) |
| Stock items, locations, par levels — edit | `menu.edit` EDIT **or** `stock.purchaseOrders` EDIT |
| Recipes — edit | `menu.edit` EDIT |
| Transfers | `stock.count` EDIT |
| Stock count: start, save lines, submit | `stock.count` EDIT |
| Stock count: post | `stock.count` APPROVE |
| Wastage log | `stock.count` EDIT (value > ₹2,000 also notifies `stock.purchaseOrders` APPROVE holders) |
| Variance and inventory summary | `stock.count` VIEW **or** `reports.view` LIMITED |
| Vendors, POs, GRNs — view | `stock.purchaseOrders` VIEW |
| PO create / edit draft / submit for approval / reorder request | `stock.purchaseOrders` REQUEST |
| PO approve / send / cancel | `stock.purchaseOrders` APPROVE |
| GRN save draft / post | `stock.purchaseOrders` REQUEST (storekeeper EDIT, chef REQUEST) |
| Vendors create/edit, debit notes settle | `stock.purchaseOrders` EDIT |

Use `@Can` for the single-key rows; for "X or Y" rows use `@Can` with the weaker common key where it exists, otherwise check in the service with `PermissionsService.check` and throw `403 PERMISSION_DENIED` (`{ permission, required }`).

### 1.7 Backend APIs

All routes are outlet-scoped from `auth.outletId` unless stated. Lists return arrays (no paging) unless `?limit=` is stated. Errors not listed use Phase 1/2 codes (`PERMISSION_DENIED`, `VALIDATION_FAILED`, `NOT_FOUND`-style codes below). JSON money values are strings with 2 dp (`"4700.00"`), stock quantities strings with 3 dp (`"6410.000"`), unit costs strings with 6 dp; every stock quantity in a view also carries a `…Display` string per 1.1.

#### Stock core (P3-A) — no routes, a service

`backend/src/modules/stock-core/stock-ledger.service.ts` exported from `StockCoreModule` (`@Global()`), injectable `StockLedgerService`:

```ts
export interface MovementInput {
  locationId: string; stockItemId: string; type: StockMovementType; qty: Prisma.Decimal; // signed
  unitCost?: Prisma.Decimal;   // receipts only; others use avgCost
  refType?: string; refId?: string; note?: string;
}
export interface MovementContext { tenantId: string; outletId: string; userId: string | null; now: Date; }

post(tx, ctx, inputs: MovementInput[]): Promise<StockMovement[]>   // writes rows, upserts StockLevel, applies WAC for RECEIPT, low-stock + auto-un-86 checks
deductForSentItems(tx, ctx, items: { orderItemId: string; productId: string | null; variantId: string | null; quantity: number; modifiers: { optionId?: string }[]; station: string }[]): Promise<{ eightySixed: { productId: string; name: string }[] }>
reverseSale(tx, ctx, orderItemIds: string[], reason: string): Promise<void>   // SALE_REVERSAL + WASTAGE + WastageEntry(VOID)
salesLocationFor(tx, outletId, station): Promise<string | null>
onHand(tx, locationId, stockItemId): Promise<Prisma.Decimal>
```

Realtime events from the ledger (`menu.item86`, `stock.low`) are returned to the caller **and** queued in an `afterCommit` list: `post()`/`deductForSentItems()` push to `ctx.events?: RealtimeEvent[]` (add `events?: RealtimeEvent[]` to `MovementContext`); the caller emits them after the transaction with `RealtimeService.emitToOutlet` (P3-C). Pure helpers in `backend/src/modules/stock-core/stock-math.ts` (unit-tested): `formatQty(qty, unit, packSize, packName)`, `weightedAverage(onHand, avgCost, qty, unitCost)`, `recipeQty(lineQty, wastagePercent, quantity)`, `varianceRow(movements[], openingQty)` → `{ opening, received, transfersIn, transfersOut, sold, wastage, expected, countAdjust, counted, variance, varianceValue }`, `toBase(purchaseQty, purchaseUnitQty)`, `nextDocNumber(prefix, n)` → `"PO-0318"` (4 digits min).

`backend/src/modules/stock-core/document-number.repository.ts`: `next(tx, tenantId, key): Promise<number>` (upsert + increment, atomic).

#### Inventory (P3-B)

| Method | Path | Body / query | Returns | Errors |
|---|---|---|---|---|
| GET | `/inventory/summary` | — | `{ stockValue, pourCost7d: { percent: "21.4", cost, revenue }, liquorVariance7d: { qty, value }, belowParCount }` | |
| GET | `/stock/locations` | — | `[{ id, name, kind, stations, isDefaultSales, itemCount, value }]` | |
| POST | `/stock/locations` | `{ name, kind, stations?, isDefaultSales? }` | location | `409 LOCATION_EXISTS` |
| PUT | `/stock/locations/:id` | same | location | |
| GET | `/stock/items` | `?locationId&search&status=BELOW_PAR|VARIANCE|EXPIRES|NEGATIVE|OK&liquor=true` | `[StockItemRow]` | |
| GET | `/stock/items/:id` | — | `StockItemDetail` | `404 STOCK_ITEM_NOT_FOUND` |
| POST | `/stock/items` | `StockItemInput` (+ `opening?: [{ locationId, qty }]`) | detail | `409 STOCK_ITEM_EXISTS` |
| PUT | `/stock/items/:id` | `StockItemInput` | detail | |
| PUT | `/stock/items/:id/par` | `{ levels: [{ locationId, parLevel }] }` | detail | |
| GET | `/stock/items/:id/movements` | `?locationId&from&to&limit=100` | `[{ id, type, qty, qtyDisplay, unitCost, value, refType, refId, note, businessDate, createdAt, createdBy }]` | |
| GET | `/stock/transfers` | `?from&to` | `[TransferView]` | |
| POST | `/stock/transfers` | `{ fromLocationId, toLocationId, note?, lines: [{ stockItemId, qty }] }` (base units) | `TransferView` | `400 SAME_LOCATION`, `400 EMPTY_TRANSFER` |
| GET | `/stock/counts` | `?status&locationId` | `[CountSummary]` | |
| POST | `/stock/counts` | `{ locationId }` | `CountView` (lines for every active item with a level row or par at that location) | `409 COUNT_ALREADY_OPEN` (`{ countId }`) |
| GET | `/stock/counts/:id` | — | `CountView` | `404 COUNT_NOT_FOUND` |
| PUT | `/stock/counts/:id/lines` | `{ lines: [{ stockItemId, countedQty: string \| null, note?, confirmedOutlier?, countedAt? }] }` (idempotent upsert; offline replays send the same body) | `CountView` | `409 COUNT_NOT_OPEN` |
| POST | `/stock/counts/:id/submit` | — | `CountView` (snapshots `expectedQty`) | `409 COUNT_NOT_OPEN`, `400 NOTHING_COUNTED` |
| POST | `/stock/counts/:id/post` | — | `CountView` (+ `COUNT_ADJUST` movements) | `409 COUNT_NOT_SUBMITTED` |
| POST | `/stock/counts/:id/cancel` | — | `CountView` | `409 COUNT_POSTED` |
| GET | `/stock/wastage` | `?from&to&locationId` | `[WastageView]` + header totals in `{ items, totalValue }` | |
| POST | `/stock/wastage` | `{ locationId, stockItemId, qty, reason, note?, photoUrl? }` | `WastageView` | `400 PHOTO_REQUIRED` (value > ₹2,000 without photo), `409 INSUFFICIENT_STOCK` (`{ onHand, onHandDisplay }`, when qty > onHand), `400 INVALID_REASON` (`VOID`, `DAMAGED_DELIVERY` are system-only) |
| POST | `/stock/uploads` | multipart `file` (jpg/png/pdf ≤ 8 MB) | `{ url }` — saved via `STORAGE_SERVICE` folder `stock` | `400 INVALID_FILE` |
| GET | `/stock/variance` | `?locationId&from&to&liquor=true` (default last 7 business days, liquor only) | `{ from, to, rows: [VarianceRow], totals: { varianceValue } }` | |
| GET | `/stock/kegs` | — | `[{ stockItemId, name, fullKegs, onTapMl, onTapDisplay, locationBreakdown: [{ locationId, name, qty, qtyDisplay }] }]` (isKeg items) | |
| GET | `/products/:id/recipes` | — | `[RecipeView]` (one per variant that has a recipe, plus `variantId: null`) with costing | |
| PUT | `/products/:id/recipes` | `{ recipes: [{ variantId: string \| null, note?, lines: [{ stockItemId, qty, wastagePercent }] }] }` (replaces all) | `[RecipeView]` | `400 RECIPE_DUPLICATE_VARIANT` |
| PUT | `/modifier-groups/:id` (existing, Phase 2) | each option may now carry `stockItemId`, `stockQty` | existing shape + those keys | |

Shapes:

```ts
StockItemInput = { name, sku?, categoryName?, baseUnit, packSize, packName, purchaseUnitName, purchaseUnitQty,
                   costingMethod, preferredVendorId?, isLiquor, isKeg, shelfLifeDays?, isActive }
StockItemRow = { id, name, categoryName, baseUnit, packSize, packName, isLiquor, isKeg,
                 onHand, onHandDisplay, parLevel, parDisplay, avgCost, unitCostDisplay /* "₹3,120 / btl" */,
                 value, status: 'OK'|'BELOW_PAR'|'VARIANCE'|'EXPIRES'|'NEGATIVE', locationId? }
   // without ?locationId: totals across the outlet's locations. VARIANCE = a posted count in the last 7 days
   // had |varianceValue| ≥ ₹500 for this item. EXPIRES = a GRN line with expiry within 7 days and stock > 0.
StockItemDetail = StockItemRow & StockItemInput & { preferredVendor: { id, name } | null,
                 levels: [{ locationId, locationName, onHand, onHandDisplay, parLevel }], lastPurchaseRate }
TransferView = { id, number, fromLocation: { id, name }, toLocation: { id, name }, note, createdAt, createdBy: { id, name },
                 lines: [{ stockItemId, name, qty, qtyDisplay, value }] }
CountSummary = { id, location: { id, name }, status, businessDate, startedBy: { id, name }, countedLines, totalLines, submittedAt, postedAt }
CountView = CountSummary & { lines: [{ stockItemId, name, baseUnit, packSize, packName, countedQty, countedDisplay,
                 expectedQty, expectedDisplay, differencePercent /* null until both known */, outlier /* |diff| > 30% */,
                 confirmedOutlier, note, countedAt }], varianceValue /* after post */ }
WastageView = { id, location: { id, name }, stockItem: { id, name }, qty, qtyDisplay, value, reason, note, photoUrl, createdAt, createdBy: { id, name } }
VarianceRow = { stockItemId, name, baseUnit, opening, received, transfersIn, transfersOut, sold, wastage, expected,
                counted /* null */, variance, varianceDisplay, varianceValue, unitCost }   // every qty also *Display
RecipeView = { variantId, variantName, note, lines: [{ stockItemId, name, baseUnit, qty, wastagePercent, cost }],
               costPerServing, sellingPrice, pourCostPercent /* cost ÷ price excl. tax × 100, 1 dp */, marginPercent }
```

#### Procurement (P3-B)

| Method | Path | Body / query | Returns | Errors |
|---|---|---|---|---|
| GET | `/vendors` | `?active=true` | `[VendorView]` | |
| POST / PUT | `/vendors`, `/vendors/:id` | `{ name, contactName?, phone?, email?, gstin?, address?, paymentTermsDays?, isActive? }` | `VendorView` | `409 VENDOR_EXISTS` |
| GET | `/purchase-orders` | `?status&vendorId` | `{ counts: { DRAFT: 3, SENT: 5, … }, items: [PoSummary] }` | |
| GET | `/purchase-orders/:id` | — | `PoView` | `404 PO_NOT_FOUND` |
| POST | `/purchase-orders` | `{ vendorId, locationId, dueDate?, transportPermitNo?, note?, lines: [{ stockItemId, qty, rate }] }` | `PoView` (DRAFT) | `400 EMPTY_PO` |
| PUT | `/purchase-orders/:id` | same | `PoView` | `409 PO_NOT_EDITABLE` (only DRAFT / PENDING_APPROVAL; editing PENDING_APPROVAL returns it to DRAFT) |
| DELETE | `/purchase-orders/:id` | — | `{ success: true }` | `409 PO_NOT_EDITABLE` (only DRAFT) |
| POST | `/purchase-orders/:id/submit` | — | `PoView` (PENDING_APPROVAL; notifies `stock.purchaseOrders` approvers) | `409 PO_NOT_EDITABLE` |
| POST | `/purchase-orders/:id/approve` | — | `PoView` (APPROVED) | `409 PO_NOT_PENDING` |
| POST | `/purchase-orders/:id/send` | — | `PoView` (SENT; allowed from APPROVED, or from DRAFT/PENDING_APPROVAL when the caller has APPROVE — auto-approves) | `409 PO_NOT_APPROVED` |
| POST | `/purchase-orders/:id/cancel` | `{ reason }` | `PoView` | `409 PO_RECEIVED` |
| GET | `/purchase-orders/reorder-suggestions` | `?locationId` (default: all) | `[{ stockItemId, name, locationId, locationName, onHand, onHandDisplay, parLevel, parDisplay, suggestedQty /* purchase units, ceil((par − onHand) ÷ purchaseUnitQty), min 1 */, purchaseUnitName, vendor: { id, name } \| null, rate /* lastPurchaseRate ?? 0 */ }]` | |
| POST | `/purchase-orders/reorder-request` | `{ locationId, lines: [{ stockItemId, qty }] }` | `{ purchaseOrders: [PoSummary] }` — one PENDING_APPROVAL PO per preferred vendor; lines without a vendor are refused | `400 VENDOR_MISSING` (`{ stockItemIds }`) |
| GET | `/grns` | `?from&to&vendorId` | `[GrnSummary]` | |
| GET | `/grns/:id` | — | `GrnView` | `404 GRN_NOT_FOUND` |
| POST | `/grns` | `{ poId?, vendorId?, locationId?, vendorInvoiceNo?, invoiceDate?, receivedOn?, transportPermitNo?, invoicePhotoUrl?, invoiceValue?, lines?: [GrnLineInput] }` — with `poId` and no lines, lines are pre-filled from the PO's outstanding qty (`orderedQty = qty − receivedQty`, `invoicedQty = receivedQty = orderedQty`) | `GrnView` (DRAFT) | `409 PO_NOT_RECEIVABLE` (PO not SENT / PARTLY_RECEIVED / INVOICE_MISMATCH) |
| PUT | `/grns/:id` | same as POST minus `poId` | `GrnView` | `409 GRN_POSTED` |
| POST | `/grns/:id/post` | — | `GrnView` | `409 GRN_POSTED`, `400 INVOICE_NO_REQUIRED`, `400 PERMIT_REQUIRED` (when any line's item `isLiquor`), `400 INVALID_QTY` (`{ line, field }` for negatives or damaged > received) |
| GET | `/debit-notes` | `?status` | `[DebitNoteView]` | |
| POST | `/debit-notes/:id/settle` | — | `DebitNoteView` | |

`GrnLineInput = { poLineId?, stockItemId, orderedQty, invoicedQty, receivedQty, damagedQty, rate, batch?, expiry? }`

**GRN post** (one transaction):
1. Validate (above). For each line with `receivedQty > 0`: `RECEIPT` movement of `toBase(receivedQty)` at `unitCost = rate ÷ purchaseUnitQty` into the GRN location (`refType 'GRN_LINE'`). Update `StockItem.lastPurchaseRate = rate`.
2. For each line with `damagedQty > 0`: `WASTAGE` movement of `toBase(damagedQty)` and a `WastageEntry` (reason `DAMAGED_DELIVERY`, value = damagedQty × rate).
3. `receivedValue = Σ receivedQty × rate`; `damagedValue = Σ damagedQty × rate`; `debitNoteAmount = Σ max(0, invoicedQty − receivedQty) × rate`; if > 0 create one `DebitNote` (reason lists each short line). `invoiceValue` defaults to `Σ invoicedQty × rate` when not given. `payable = invoiceValue − debitNoteAmount`. `mismatch = any invoicedQty ≠ orderedQty` or `|invoiceValue − Σ invoicedQty × rate| > ₹1`.
4. PO: add `receivedQty` to each `poLineId`; status `INVOICE_MISMATCH` if `mismatch`, else `RECEIVED` when every line `receivedQty ≥ qty`, else `PARTLY_RECEIVED`.
5. The design example must hold: Lager 10 cs ordered/invoiced/received, 1 damaged; keg 4 ordered, 5 invoiced, 4 received at ₹7,800; Stout 4 cs → receipts of 14 cases, minus 1 damaged case written off as wastage = net +13 cases, and +4 kegs in the Cellar, debit note ₹7,800, wastage ₹950, payable ₹66,900 − ₹7,800 = ₹59,100.

```ts
VendorView = { id, name, contactName, phone, email, gstin, address, paymentTermsDays, isActive, openPoCount }
PoSummary = { id, number, vendor: { id, name }, location: { id, name }, total, dueDate, status, createdAt }
PoView = PoSummary & { transportPermitNo, note, createdBy, approvedBy, approvedAt, sentAt,
         lines: [{ id, stockItemId, name, purchaseUnitName, qty, rate, total, receivedQty }], grns: [GrnSummary] }
GrnSummary = { id, number, poNumber, vendor: { id, name }, location: { id, name }, status, receivedOn, invoiceValue, payable, mismatch }
GrnView = GrnSummary & { poId, vendorInvoiceNo, invoiceDate, transportPermitNo, invoicePhotoUrl, poValue, receivedValue,
          debitNoteAmount, damagedValue, lines: [GrnLineInput & { id, name, purchaseUnitName, status: 'OK'|'SHORT'|'OVER_INVOICED'|'DAMAGED' }],
          preview: { stockAdded: [{ name, qty, display }], debitNote, wastage, payable } }   // computed for DRAFT too
DebitNoteView = { id, number, vendor: { id, name }, grnNumber, amount, reason, status, createdAt }
```

#### Bar tabs and bottle locker (P3-C)

| Method | Path | Body / query | Returns | Errors |
|---|---|---|---|---|
| GET | `/tabs` | `?status=OPEN|CLOSED&scope=today&openedById` | `{ counts: { open, nearLimit, closedToday }, items: [TabView] }` | |
| GET | `/tabs/:id` | — | `TabView` (+ `order: OrderView`) | `404 TAB_NOT_FOUND` |
| POST | `/tabs` | `{ guestName, mobile?, ageChecked, security, cardLast4?, amountHeld?, houseAccount?, tabLimit, warnAtPercent, linkType, linkLabel?, tableId?, approvalId? }` | `TabView` — creates a `BAR_COUNTER` order (`DINE_IN` when `linkType TABLE`, with `tableId`), `order.note = "Tab T-07 · Karthik R"` | `400 AGE_CHECK_REQUIRED`, `400 CARD_LAST4_REQUIRED`, `400 DEPOSIT_REQUIRED` (CASH_DEPOSIT without amountHeld > 0), `400 HOUSE_ACCOUNT_REQUIRED`, `403 LIMIT_EXCEEDED`, `403 APPROVAL_REQUIRED` (security NONE) |
| PUT | `/tabs/:id` | `{ guestName?, mobile?, tabLimit?, warnAtPercent?, linkType?, linkLabel?, tableId? }` | `TabView` | `409 TAB_CLOSED`, `403 LIMIT_EXCEEDED` |
| POST | `/tabs/:id/move-to-table` | `{ tableId }` | `TabView` (order type → DINE_IN, tableId set, table OCCUPIED, linkType TABLE) | `409 TABLE_OCCUPIED` |
| POST | `/tabs/:id/close` | — | `{ tab: TabView, orderId, depositApplied, depositToReturn }` — bills the order (Phase 2 bill logic), applies a cash deposit as a `CASH` payment with `reference: 'TAB_DEPOSIT'` for `min(amountHeld, grandTotal)` through `PaymentsService`, `depositToReturn = amountHeld − applied`; the tab becomes CLOSED when the order is fully paid (immediately, or later on payment — `PaymentsService` calls `TabsService.onOrderPaid(tx, orderId)`) | `409 TAB_CLOSED`, `400 TAB_EMPTY` |
| POST | `/tabs/:id/void` | `{ reason }` | `TabView` | `409 TAB_NOT_EMPTY` (only empty tabs) |
| GET | `/locker` | `?status=ACTIVE&search` | `[LockerView]` | |
| POST | `/locker` | `{ guestName, mobile?, cardLast4?, stockItemId?, bottleName, bottleMl, remainingMl, expiresAt, orderItemId?, note? }` | `LockerView` | `400 INVALID_ML` |
| POST | `/locker/:id/serve` | `{ ml }` | `LockerView` (FINISHED at 0) | `409 NOT_ENOUGH_LEFT` (`{ remainingMl }`), `409 LOCKER_EXPIRED` |
| PUT | `/locker/:id` | `{ guestName?, mobile?, remainingMl?, expiresAt?, note? }` (remainingMl change writes an ADJUST event) | `LockerView` | |
| DELETE | `/locker/:id` | `{ reason }` | `LockerView` (REMOVED) | |

```ts
TabView = { id, number, guestName, mobile, ageChecked, security, cardLast4, amountHeld, houseAccount, tabLimit, warnAtPercent,
            spent /* order.grandTotal */, remaining, percentUsed, nearLimit /* percentUsed ≥ warnAtPercent */,
            linkType, linkLabel, table: { id, name } | null, status, openedAt, closedAt, openedBy: { id, name }, orderId,
            orderStatus, itemCount }
LockerView = { id, guestName, mobile, cardLast4, guestLabel /* "Vikram S · ••7720" */, stockItemId, bottleName, bottleMl,
               remainingMl, storedAt, expiresAt, status, expired /* expiresAt < today */, events: [{ kind, ml, by, note, createdAt }] }
```

**Tab limit enforcement** (P3-C, inside `OrdersService.addItems` and `updateItem` after re-pricing, same transaction): if the order has an OPEN tab and the new `grandTotal > tabLimit` → throw `409 TAB_LIMIT_REACHED` `{ tabId, number, limit, spent, attempted }` (the transaction rolls back). When `grandTotal ≥ tabLimit × warnAtPercent / 100` and `warnedAt` is null → set `warnedAt`, create a Notification (`type 'alert'`, `userId = tab.openedById`, title `"Tab T-07 is at 94% of its ₹5,000 limit"`) and emit `tab.nearLimit` after commit. `OrderView` gains `tab: { id, number, tabLimit, spent, nearLimit } | null` (P3-C edits `order-view.ts`).

**Tab number:** `T-` + 2-digit (or more) count of tabs at the outlet for the business date + 1.

#### KDS (P3-C)

| Method | Path | Body / query | Returns | Errors |
|---|---|---|---|---|
| GET | `/kds/tickets` | `?station=BAR|KITCHEN|…|ALL&view=active|done` (active = NEW, PREPARING, READY; done = SERVED in the last 2 h) | `{ serverTime, tickets: [KdsTicket], allDay: [{ name, variantName, quantity }], avgTicketSeconds }` | |
| POST | `/kds/tickets/:id/start` | — | `KdsTicket` (NEW → PREPARING, `startedAt`) | `409 KDS_BAD_STATE` (`{ status }`) |
| POST | `/kds/tickets/:id/bump` | — | `KdsTicket` (NEW or PREPARING → READY, `readyAt`; notifies the waiter) | `409 KDS_BAD_STATE` |
| POST | `/kds/tickets/:id/recall` | — | `KdsTicket` (READY or SERVED → PREPARING, `recalledAt`, clears `readyAt`/`servedAt`; SERVED only within 30 min) | `409 KDS_BAD_STATE`, `409 RECALL_TOO_LATE` |
| POST | `/kds/tickets/:id/served` | — | `KdsTicket` (READY → SERVED, `servedAt`, its non-voided order items → `SERVED`) | `409 KDS_BAD_STATE` |
| GET | `/kds/ready` | `?mine=true` | `[ReadyItem]` — READY tickets of the outlet (mine = order.waiterId or ticket.createdById is me) | |
| GET | `/kds/stations` | — | `[{ station, label, activeCount }]` — distinct `Category.station` values of the tenant plus counts | |

```ts
KdsTicket = { id, kind, station, seq, label /* `${kind} ${seq}`, e.g. "BOT 12" */, kdsStatus,
              order: { id, orderNumber, type, tableName, tabNumber, waiterName, covers },
              items: [{ orderItemId, name, variantName, quantity, modifiers: string[], note, seat, voided: boolean }],
              createdAt, startedAt, readyAt, servedAt, ageSeconds, colour: 'green'|'amber'|'red' /* < 5 min, 5–10, > 10 from createdAt to now (or to readyAt) */ }
ReadyItem = { ticketId, label, station, tableName, tabNumber, items: [{ name, variantName, quantity, seat }], readyAt, waitingSeconds, overdue /* > 5 min */ }
```

Cancellation tickets (`isCancellation = true`) are not returned as cards; their lines show as `voided: true` (struck through) on the original ticket via the order item status `VOIDED`. Phase 2 printing is unchanged — a station may have both a printer and a KDS.

**Ready alert:** on bump → `Notification` (`type 'ready'`, `userId = order.waiterId ?? ticket.createdById`, title `"Ready at the bar · R4"`, body = items) and realtime `kds.ready` to `user:<id>` and the outlet. **Overdue:** an interval in `KdsService.onModuleInit` (every 60 s, `setInterval`, cleared on destroy, skipped when `process.env.NODE_ENV === 'test'`) finds READY tickets with `readyAt < now − 5 min` and `overdueAlertedAt` null → Notification (`type 'alert'`, `permissionKey 'kds.bump'`, title `"R4 · drinks waiting 6 min"`), sets `overdueAlertedAt`.

#### Realtime (P3-C)

- Add to `backend/package.json` dependencies: `"@nestjs/websockets": "^10.3.0"`, `"@nestjs/platform-socket.io": "^10.3.0"`, `"socket.io": "^4.7.5"`. (The integrator notes that `npm install` is needed.)
- `backend/src/modules/realtime/realtime.gateway.ts`: `@WebSocketGateway({ namespace: '/rt', cors: { origin: true, credentials: true } })`. On connection read `socket.handshake.auth.token` (JWT, same secret as `JwtStrategy`; reuse its payload → AuthUser mapping by reading `backend/src/modules/auth/*`), reject (disconnect) when missing/invalid or without `outletId`. Join rooms `outlet:<outletId>`, `user:<userId>`, and for `handshake.auth.stations` (string array, optional) `outlet:<outletId>:station:<s>`.
- `RealtimeService` (`@Global()` module `RealtimeModule`): `emitToOutlet(outletId, event, payload)`, `emitToStation(outletId, station, event, payload)`, `emitToUser(userId, event, payload)`; no-ops (debug log) when the server isn't initialised (unit tests).
- `type RealtimeEvent = { scope: 'outlet' | 'station' | 'user'; outletId?: string; station?: string; userId?: string; event: string; payload: unknown }`, exported from `backend/src/modules/realtime/realtime.types.ts` (P3-C) — **P3-A imports this type**; if P3-A runs first it may create the file with exactly this content and P3-C keeps it.
- Events: `kds.ticket.created` (KdsTicket, outlet + station) — emitted from `OrdersService` after commit for every new ticket (send, voids create cancellation → emit `kds.ticket.updated` for the original tickets instead); `kds.ticket.updated` (KdsTicket); `kds.ready` (ReadyItem); `menu.item86` (`{ productId, name, is86, auto }`); `stock.low` (`{ stockItemId, name, locationId, locationName, onHand, parLevel }`); `tab.nearLimit` (TabView); `order.updated` (`{ orderId, status }`) after send/bill/pay.
- Manual 86 (Phase 2 `PATCH /products/:id/86` or similar in the products module) also emits `menu.item86` — P3-C adds one line there.

#### Orders integration (P3-C)

- `send`: inside the transaction, after tickets are created and items set SENT, call `stockLedger.deductForSentItems(tx, ctx, …)` with each item's ticket station; after commit emit `kds.ticket.created` per ticket and collected ledger events.
- `voidItems` / `voidOrder`: call `stockLedger.reverseSale(tx, ctx, sentItemIds, reason)` for lines that were SENT; emit `kds.ticket.updated` for the affected original tickets.
- `PaymentsService.settle` on full payment: `tabs.onOrderPaid(tx, orderId)` (closes the tab).
- `OrderView.tab` (above).

### 1.8 Seed (P3-A, idempotent, extends `prisma/seed.ts`)

For the default tenant/outlet: vendors Metro Spirits Distributors, City Breweries Supply, Fresh Farm Produce, Glassware Co.; stock items with opening stock and par: House Whisky 750 ml (ML, pack 750 btl, Case of 12 = 9000, ₹1,100/btl, Bar 6 btl par 6, Main store 24 btl), Single Malt 12Y 750 ml (₹3,120/btl → avgCost 4.16, Bar 3 btl par 6, Main store 12), Premium Vodka 750 ml (₹1,450/btl, Bar 8 btl + 410 ml, par 12), Dark Rum 750 ml, White Rum 750 ml, Premium Lager 650 ml (pack 650 btl, Case of 12, Cellar 10 cs), Stout 500 ml, Wheat beer keg 30 L (isKeg, pack 30000 keg, ₹7,800/keg, Cellar 3 kegs), Soda 200 ml (ML, pack 200 "btl"), Sugar syrup (ML pack 1000 "btl"), Fresh mint (G, pack 1000 "kg pack", Bar 600 g par 1000), Lime (PC), Chicken wings (G, Kitchen 5000 g), Paneer (G, Kitchen 2000 g). Mark spirits/beer `isLiquor`. Recipes: House Whisky 30 ml → 30 ml (2% wastage), 60 ml → 60 ml (2%), Bottle → 750 ml; Single Malt 30/60 ml likewise; Premium Lager → 650 ml; Classic Mojito → White rum 60 ml, Fresh mint 8 g, Sugar syrup 20 ml, Soda 100 ml, Lime 1 pc; Chicken Wings (8 pc) → 400 g chicken wings; Paneer Tikka → 250 g paneer (create the product in category Bar bites if the Phase 2 seed lacks it). Modifier option "With soda" → Soda 200 ml. One SENT PO-0317 (City Breweries Supply → Cellar: Premium Lager 10 cs ₹3,800, Wheat beer keg 4 × ₹7,800, Stout 4 cs ₹3,400) so the GRN example can be replayed. Opening stock is written through `OPENING` movements (seed may write rows directly with the same rules — no service DI in the seed). Set `DocumentCounter PO = 317`.

### 1.9 Frontend contracts

**Shared helpers (P3-E owns, P3-D may import):** `frontend/lib/features/inventory/data/stock_format.dart` — `String formatStockQty(num qty, String unit, num packSize, String packName)` identical to 1.1; `num parseStockInput(int bottles, num openPart, num packSize)`.

**Realtime client (P3-D owns):** `frontend/lib/core/realtime/realtime_client.dart` using `socket_io_client: ^2.0.3` (P3-D adds it to `pubspec.yaml`). `realtimeClientProvider` (Riverpod) connects to `<apiBase origin>/rt` with `auth: { token, stations }` after login, reconnects with back-off, exposes `Stream<RealtimeEvent> on(String event)` (`RealtimeEvent { String event; Map<String, dynamic> payload; }`) and `ValueListenable<bool> connected`. Screens that rely on it **also poll** (KDS every 5 s, ready list every 10 s) while `connected` is false. Read the existing `dioProvider` / API base config to get the URL and token.

**Data layers:**
- P3-D: `features/tabs/data/tabs_models.dart` (`TabView`, `TabsPage { counts, items }`, `LockerView`, `LockerEvent`), `features/tabs/data/tabs_repository.dart` (`TabsRepository`, `tabsRepositoryProvider`, one method per tab/locker endpoint); `features/kds/data/kds_models.dart` (`KdsTicket`, `KdsItem`, `KdsBoard { serverTime, tickets, allDay, avgTicketSeconds }`, `ReadyItem`, `KdsStation`), `features/kds/data/kds_repository.dart` (`KdsRepository`, `kdsRepositoryProvider`).
- P3-E: `features/inventory/data/inventory_models.dart` (every inventory shape in 1.7 incl. `RecipeView`), `features/inventory/data/inventory_repository.dart` (`InventoryRepository`, `inventoryRepositoryProvider`), `features/inventory/data/offline_count_queue.dart` (`OfflineCountQueue`, Hive box `offline_stock_counts`: stores `{ countId, stockItemId, countedQty, note, confirmedOutlier, countedAt }` per line, `flush()` sends one `PUT /stock/counts/:id/lines` per count on reconnect / every 30 s / on screen open, keeps lines on failure; UI banner "You're offline. 18 counts are saved on this phone and will sync when you reconnect. Keep counting."); `features/procurement/data/procurement_models.dart`, `features/procurement/data/procurement_repository.dart` (`ProcurementRepository`, `procurementRepositoryProvider`).
- Money/qty JSON strings parse to `String` + `num get …Amount` like Phase 2 models. Errors are Phase 1 `ApiError` (`code`, `message`, `details`).

**Screens and routes** (P3-E owns `core/router/app_router.dart`, `core/shell/nav_registry.dart`, `test/shell/nav_filter_test.dart`):

| Route | Class | File | Owner |
|---|---|---|---|
| `/tabs` | `BarTabsScreen` (filter chips Open / Near limit / Closed today, bartender filter, tabs table/cards per BarTabs board with Add items → `/pos/<orderId>`, Edit, Close & pay → `POST /tabs/:id/close` then `/pos/<orderId>/pay`, Move to table; second tab "Bottle locker" with Store bottle, Serve (ml stepper 30/60/90/custom), Edit, Remove) | `features/tabs/presentation/bar_tabs_screen.dart` | P3-D |
| — dialog | `showOpenTabDialog(context, {String? linkLabel, String? tableId})` → `TabView?` (form per board; security radio; "None (manager approval)" uses `showManagerPinDialog` from `features/pos/presentation/dialogs/manager_pin_dialog.dart` with approval type `TAB_NO_SECURITY`; limit above the persona limit shows "₹10,000 is above your ₹5,000 limit"; shows `LIMIT_EXCEEDED` / `AGE_CHECK_REQUIRED` errors inline) | `features/tabs/presentation/open_tab_dialog.dart` | P3-D |
| `/kds` | `KdsScreen` (station chips All/Kitchen/Bar/Grill/Tandoor from `/kds/stations`; three columns New / Preparing / Ready to serve; ticket cards with age timer ticking every second from `serverTime` offset, colour green/amber/red, struck voided lines, buttons Start / Bump / Recall / Served; all-day counts side panel; avg ticket time; full-screen toggle; `?station=BAR` query preselects) | `features/kds/presentation/kds_screen.dart` | P3-D |
| `/service/ready` | `ReadyToServeScreen` (MobileStaff "Ready alert & mark served": cards per ready ticket with table, items, seat, waiting time, Served button; Mine / All toggle; overdue red) | `features/kds/presentation/ready_to_serve_screen.dart` | P3-D |
| `/menu/availability` | `AvailabilityScreen` (TabletOps chef board: tonight's items with Available / Sold out toggle via the Phase 2 86 endpoint, "auto" badge for auto-86, filter by station; "Log kitchen wastage" button → `showLogWastageSheet` from P3-E) | `features/menu/presentation/availability_screen.dart` | P3-D |
| `/inventory` | `InventoryScreen` (KPI tiles from `/inventory/summary`; tabs Stock items · Locations · Transfers · Stock counts · Wastage · Variance report · Kegs & empties; stock items table with location filter, status chips, "8 btl + 410 ml" display, row tap → editor) | `features/inventory/presentation/inventory_screen.dart` (+ one file per tab in `features/inventory/presentation/tabs/`) | P3-E |
| `/inventory/items/:id` (`new` for create) | `StockItemEditorScreen` (fields per Inventory board edit panel: name, category, base unit, pack size/name, purchase unit name + qty, count unit, par per location, costing method + FIFO note, preferred vendor, liquor, keg, shelf life; movements list) | `features/inventory/presentation/stock_item_editor_screen.dart` | P3-E |
| `/stock-count` | `StockCountScreen` (replaces the placeholder; pick location → start/continue count; MobileStock layout: progress "18 of 42 items counted", bottles stepper + "ml open" field per item, status Saved offline / Not counted / Check again, outlier warning "Expected about 3 bottles. This count is 60% lower. Recount, or add a note." with Add note / Count is correct; Save & exit; Submit when online; managers see Post) | `features/inventory/presentation/stock_count_screen.dart` | P3-E |
| — sheet | `showLogWastageSheet(context, {String? locationId, String? stockItemId})` → `bool` (MobileStaff: item picker, quantity in pack + part, `INSUFFICIENT_STOCK` message "Only 2 full bottles in Bar stock…", reason chips Broken/Spilled/Expired/Comp/Staff meal/Burnt/Dropped/Returned, photo via `pickImageFile` from `core/files/pick_file.dart` → `POST /stock/uploads`, "Add photo (needed above ₹2,000)", value preview "Value about ₹7,800 · Manager gets notified") | `features/inventory/presentation/log_wastage_sheet.dart` | P3-E |
| `/procurement` | `ProcurementScreen` (tabs Purchase orders · Goods received · Vendors · Debit notes; status count chips; "Reorder suggestions (9)" button → `ReorderScreen`; "New purchase order") | `features/procurement/presentation/procurement_screen.dart` | P3-E |
| `/procurement/reorder` | `ReorderScreen` (MobileStaff "Request a reorder": below-par list, qty stepper in purchase units, vendor per line, "Creates 2 draft POs (one per vendor), ₹65,400 total. A manager approves before they're sent.", Send for approval) | `features/procurement/presentation/reorder_screen.dart` | P3-E |
| `/procurement/po/:id` (`new`) | `PurchaseOrderScreen` (Procurement board PO editor: vendor, deliver to, delivery date, transport permit, lines with item/qty/rate/total, Add from reorder list, Delete draft / Save draft / Submit for approval / Approve / Send to vendor according to status + permission) | `features/procurement/presentation/purchase_order_screen.dart` | P3-E |
| `/procurement/grn/:id` (`new?poId=`) | `GrnScreen` (GRN + TabletOps receiving: invoice photo capture/upload first on narrow screens, lines table Ordered / Invoiced / Received / Damaged / Batch / Expiry with status chips and inline validation "Must be 0 or more", live preview text "Posting creates: stock +13 cases +4 kegs in Cellar, a debit note of ₹7,800 for the missing keg, and ₹950 wastage for the damaged case.", delivery details, PO value / invoice value / payable, Save draft / Post GRN) | `features/procurement/presentation/grn_screen.dart` | P3-E |
| `/menu/products/:id` (existing) | add a **Recipe** section/tab to `ProductEditorScreen`: per variant (and "All variants"), ingredient rows (stock item picker, qty, unit label from base unit, cost), wastage allowance %, selling price, cost per drink, pour cost %, margin %; helper text "Each sale deducts these amounts from Bar stock. That's what the variance report compares against."; Save calls `PUT /products/:id/recipes`. Modifier group editor gets an optional "Stock" column (item + qty) per option | `features/menu/presentation/product_editor_screen.dart` (+ `features/menu/presentation/widgets/recipe_editor.dart`), `features/menu/presentation/modifier_groups_screen.dart` | P3-E |

**POS integration (P3-D, edits in `features/pos/**`):** `OrderView` model gains `tab` (`OrderTabInfo { id, number, tabLimit, spent, nearLimit }`); the ticket panel header shows "Tab T-07 · ₹4,700 / ₹5,000" with a warning colour when near limit; `TAB_LIMIT_REACHED` on add shows "Tab T-07 has reached its ₹5,000 limit. Ask a manager to raise it or close the tab."; on the Bar counter order type, an **Open tab** button calls `showOpenTabDialog` and navigates to `/pos/<orderId>`; 86'd products refresh live on `menu.item86` events (invalidate the menu provider).

**Nav registry** (P3-E): add Bar tabs `/tabs` (group Sales, `sales.tab.open` VIEW, icon `Icons.local_bar_outlined`), Kitchen display `/kds` (Sales, `kds.bump` VIEW, `Icons.soup_kitchen_outlined`), Ready to serve `/service/ready` (Sales, `kds.bump` VIEW, `Icons.room_service_outlined`), Inventory `/inventory` (Menu & stock, `stock.count` VIEW, `Icons.warehouse_outlined`), Procurement `/procurement` (Menu & stock, `stock.purchaseOrders` VIEW, `Icons.local_shipping_outlined`), Availability `/menu/availability` (Menu & stock, `menu.mark86` EDIT, `Icons.toggle_on_outlined`); Stock count loses `placeholder: true`. With the default matrix the **Bartender** now sees: (recompute from the registry: count items whose permission/min the bartender matrix satisfies, starting from the Phase 2 expectation of 6) — update `test/shell/nav_filter_test.dart` with the recomputed count and list the bartender's items in your report. Chef sees Menu & products, Stock count, Kitchen display, Ready to serve, Inventory, Procurement, Availability.

---

## 2. Workstreams

Run in parallel. File ownership is exclusive.

### P3-A — Data model, migration, stock core, permissions, seed (backend)
**Owns:** `backend/prisma/**`, `backend/src/modules/stock-core/**` (new), `backend/src/common/tenancy/tenant-scope.extension.ts` (TENANT_MODELS only), `backend/src/prisma/prisma.service.ts` (loose-create list only, if Phase 2 added one), `backend/src/common/permissions/catalog.ts`, `frontend/lib/core/auth/permission_keys.dart` (one line), `backend/src/app.module.ts` (register `StockCoreModule` **and** P3-B/P3-C modules: `./modules/inventory/inventory.module` (`InventoryModule`), `./modules/procurement/procurement.module` (`ProcurementModule`), `./modules/tabs/tabs.module` (`TabsModule`), `./modules/kds/kds.module` (`KdsModule`), `./modules/realtime/realtime.module` (`RealtimeModule`)).
1. Schema + migration per 1.5 (relations, back-relations, indexes). Prisma relation names must be unique — name them (`@relation("TabOpenedBy")` etc.) wherever two relations point at the same model.
2. `stock-core`: `StockCoreModule` (`@Global()`, exports `StockLedgerService`, `DocumentNumberRepository`), `stock-ledger.service.ts`, `stock-ledger.repository.ts` (all Prisma access), `stock-math.ts`, specs `stock-math.spec.ts` (formatQty cases from 1.1, WAC incl. H ≤ 0, recipeQty, varianceRow with the 1.3 formula) and `stock-ledger.service.spec.ts` (mock repository: deduction picks variant recipe then product recipe, modifier stock, station → location fallback, auto-86 when level ≤ 0, auto un-86 on receipt, low-stock notification only on crossing, reverseSale pairs).
3. `kds.bump` permission per 1.6 (catalog, migration rows, frontend `Perm`).
4. Seed per 1.8.
5. Report `docs/phase-3/reports/P3-A.md`.

### P3-B — Inventory + procurement APIs (backend)
**Owns:** new `backend/src/modules/inventory/**` (locations, stock items, par, movements, transfers, counts, wastage, uploads, variance, kegs, summary, recipes — controllers may be split into several files, one `InventoryModule`), new `backend/src/modules/procurement/**` (vendors, POs, reorder, GRNs, debit notes — one `ProcurementModule`), edits to `backend/src/modules/modifiers/**` (option `stockItemId`/`stockQty` in DTOs, repository, view), `docs/API.md` (add `## Inventory (Phase 3)` and `## Procurement (Phase 3)` sections).
Implement every P3-B row of 1.7 using `StockLedgerService` and `DocumentNumberRepository` from P3-A (`import { StockLedgerService } from '../stock-core/stock-ledger.service'`) for every stock change — never write `StockMovement`/`StockLevel` directly. The recipes endpoints live in the inventory module (`recipes.controller.ts` with `@Controller('products/:id/recipes')`). Notifications: add a `create(data)` method in **your own** repository (Prisma `notification.create`), do not edit the notifications module. Realtime: after commit, emit ledger events with `RealtimeService` (`import { RealtimeService } from '../realtime/realtime.service'`, P3-C). Specs: GRN post math with the 1.7 design example (debit note ₹7,800, wastage ₹950, payable ₹59,100, PO → INVOICE_MISMATCH since keg invoiced 5 ≠ ordered 4), reorder suggestions rounding, reorder request groups by vendor + VENDOR_MISSING, PO status transitions + permission (REQUEST can't approve), count submit/post adjustments, wastage PHOTO_REQUIRED and INSUFFICIENT_STOCK, variance endpoint uses `varianceRow`. Report `P3-B.md`.

### P3-C — Bar tabs, bottle locker, KDS, realtime, orders integration (backend)
**Owns:** new `backend/src/modules/{tabs,kds,realtime}/**`, edits to `backend/src/modules/orders/**` (send/void hooks, tab limit, `OrderView.tab`, ticket realtime emits), `backend/src/modules/payments/payments.service.ts` (+ its module imports; `onOrderPaid` hook and deposit payment support), `backend/src/modules/products/**` (only the one `menu.item86` emit on manual 86), `backend/src/modules/approvals/**` (only if `TAB_NO_SECURITY` needs a `canonicalPayload` case / DTO enum value), `backend/package.json` (three socket deps), `docs/API.md` (add `## Bar tabs, KDS and realtime (Phase 3)`).
Implement the P3-C rows of 1.7 and the orders integration. Avoid circular module imports: `TabsModule` exports `TabsService`; `OrdersModule` imports `TabsModule` only if `TabsModule` does not import `OrdersModule` — put the tab lookups needed by orders (`tabForOrder(tx, orderId)`, limit check, warn) in a small `TabsLimitService` inside `tabs/` that depends only on its repository; the tab **close** flow (which needs orders/payments) lives in `TabsService` and uses `forwardRef` if needed. Specs: open tab validations (age, limit via `assertWithinLimit`, NONE needs approval), limit reached rolls back, near-limit warn once, close applies deposit min(held, total) and returns change, KDS transitions + bad state, recall window, all-day counts exclude served/voided, ticket colour thresholds, gateway rejects without token (unit-test the auth helper, not sockets). Report `P3-C.md`.

### P3-D — Bar tabs, KDS, ready list, availability, realtime client, POS hooks (frontend)
**Owns:** new `frontend/lib/features/{tabs,kds}/**`, `frontend/lib/core/realtime/**`, `frontend/lib/features/menu/presentation/availability_screen.dart` (new file only), edits in `frontend/lib/features/pos/**` (1.9 POS integration), `frontend/pubspec.yaml` (add `socket_io_client: ^2.0.3`), `frontend/test/{tabs,kds}/**`.
Implement the P3-D rows of 1.9 matching the BarTabs, MobileTab, KDS, MobileStaff (waiter) and TabletOps (chef 86) boards. Tests: `KdsTicket.fromJson` + colour thresholds, KDS age timer formatting (`mm:ss`), `TabView.fromJson` near-limit, open-tab form validation (age required, card last4 required for card pre-auth), offline polling switch (fake `connected` false → repository polled). Report `P3-D.md`.

### P3-E — Inventory, stock count (offline), wastage, procurement, GRN, recipe editor, router, nav (frontend)
**Owns:** new `frontend/lib/features/{inventory,procurement}/**`, edits to `frontend/lib/features/menu/presentation/product_editor_screen.dart`, `frontend/lib/features/menu/presentation/modifier_groups_screen.dart`, new `frontend/lib/features/menu/presentation/widgets/recipe_editor.dart`, `frontend/lib/features/menu/data/menu_repository.dart` (recipe + option stock fields only if the menu repository is where those calls fit; otherwise use `InventoryRepository`), `frontend/lib/core/router/app_router.dart`, `frontend/lib/core/shell/nav_registry.dart`, `frontend/test/shell/nav_filter_test.dart`, `frontend/test/{inventory,procurement}/**`.
Implement the P3-E rows of 1.9 matching the Inventory, Procurement, GRN, MobileStock, MobileStaff (wastage, reorder), TabletOps (receiving) and MenuEditors (recipe) boards. Register routes for P3-D's classes too (import paths from the table). Tests: `formatStockQty` cases (same as backend), offline count queue stores and flushes (mock repository) and keeps lines on failure, count outlier rule (> 30%), GRN preview text from a `GrnView` fixture matching the design example, nav filter counts. Report `P3-E.md`.

---

## 3. Integration (planner)
Cross-check JSON keys between backend view builders and Flutter `fromJson`, HTTP methods vs controller decorators, route classes vs imports, module registration in `app.module.ts`, migration vs schema (every model/column/enum), TENANT_MODELS; run the TS/Dart import resolution scripts; resolve report requests; write `docs/phase-3/INTEGRATION.md` (pilot test script = exit test above, install notes for socket deps, known gaps); commit and push to `phase-1-foundation`; update PR #2.

Known gaps accepted for Phase 3 (list them in INTEGRATION.md): real card pre-auth via a gateway (only last 4 + held amount recorded; the "Declined" flow uses normal payment errors); OCR "Read from photo" on GRN; FIFO costing; weight-based counting ("ml by weight"); empties/deposit tracking for kegs and bottles; vendor invoices, payables ageing and 3-way match approval (Phase 5 Accounting); brand rebates (Campaigns); 86 is tenant-wide while stock is per outlet; Phase 1b tenant scoping gaps from earlier phases.
