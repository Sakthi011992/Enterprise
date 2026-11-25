# Phase 2 — Pub POS core: detailed implementation plan

Branch: `phase-1-foundation` (Phase 2 lands in the same PR #2). Builds on Phase 1 (`docs/phase-1/PLAN.md`): tenants, outlets, personas, `@Can`, `TenantContext`, session payload, component kit, shell.

Design boards: POS, POSPay, POSApprove, Menu, MenuEditors, FloorPlan, Orders, Settings (tax/invoice/payments), Hardware, TabletPOS, Main (in `docs/ui-design/project/`).

**Exit test (pilot gate):** at one outlet, a 4-cover table R4 orders 2 lagers (BOT), wings (KOT), a happy-hour mojito and a 60 ml single malt with "On the rocks" for seat 2 → tickets print at the bar and kitchen printers → a 20% discount needs a manager PIN → the bill is split by seat, seat 2 pays by cash + UPI with a 5% tip and change shown → the rest pays by card → the invoice is numbered `INV/2026-27/000001` → X report mid-shift, Z report and day close at the end. Server totals equal the POS screen to the paisa.

---

## 0. Ground rules (same as Phase 1, plus)

1. Edit only the files your workstream owns. Requests for others go in your report.
2. No network, no Node/Flutter toolchain: write code that would compile; reread carefully.
3. Contracts in section 1 are exact (names, paths, JSON shapes, error codes).
4. Backend: **controller → service → repository**, only repositories touch Prisma (`.claude/skills/common-backend.md`). Use `@Can` from Phase 1 (`common/decorators/can.decorator.ts`), `@CurrentUser() auth: AuthUser` (has `tenantId`, `outletId`, `userId`, `permissions`), `ApiError`-style errors with `code` (see `common/filters/api-error.ts`). Money is `Prisma.Decimal`, rounded with `round2` (`common/utils/money.util.ts`), never JS floats.
5. Frontend: kit from `core/ui/ui.dart`, session from `core/auth/*` (`can`, `Perm`, `AccessLevel`, `sessionProvider`), HTTP via `dioProvider`, colours from `context.tokens`/`context.ext`. POS screens sit in `DensityScope(pos)` (52 px touch targets).
6. Don't commit. Write `docs/phase-2/reports/P2-<letter>.md` at the end.

---

## 1. Shared contracts

### 1.1 Order lifecycle

`OPEN` (items being added) → `SENT` (at least one ticket sent; more items may still be added and sent) → `BILLED` (bill printed; adding items reopens to `SENT`) → `PAID` (payments cover grand total) → `CLOSED` (table freed; automatic right after `PAID` for takeaway/bar counter, on "Close table" for dine-in) · `VOID` (whole order cancelled; needs `sales.void` APPROVE or an approval).

Item status: `NEW` → `SENT` (on Send KOT/BOT) → `SERVED` (optional) · `VOIDED`. Voiding a `SENT` item prints a cancellation ticket at its station and records wastage reason.

Legacy statuses `PENDING`, `PARTIALLY_PAID`, `REFUNDED` stay in the enum for old rows; new orders never use `PENDING`. `REFUNDED` is still set by full refunds.

### 1.2 Data model (owned by P2-A) — add to `schema.prisma`

```prisma
enum OrderType { DINE_IN BAR_COUNTER TAKEAWAY DELIVERY }
// extend existing enum OrderStatus with: OPEN SENT BILLED CLOSED VOID  (keep PENDING PAID PARTIALLY_PAID REFUNDED)
enum OrderItemStatus { NEW SENT SERVED VOIDED }
enum TicketKind { KOT BOT }
enum TicketStatus { QUEUED PRINTED FAILED CANCELLED }
enum TableStatus { FREE OCCUPIED BILL_PRINTED CLEANING RESERVED }
enum TableShape { SQUARE ROUND LONG }
enum ApprovalType { DISCOUNT VOID REFUND NO_SALE }
enum ApprovalStatus { PENDING APPROVED DECLINED EXPIRED }
enum DiscountType { PERCENT FLAT }
enum PrinterConnection { LAN USB BLUETOOTH }
enum PrintJobKind { TICKET BILL REPORT DRAWER TEST }
enum PrintJobStatus { QUEUED SENT DONE FAILED }
enum RoundingMode { NONE NEAREST_1 }
enum DayCloseKind { X Z }

model TaxClass {            // "tax rules" on the Settings board
  id          String   @id @default(uuid())
  tenantId    String
  name        String   // "GST 5% (restaurant)"
  code        String   // "GST5", "VAT_LIQUOR", "GST18"
  rate        Decimal  @db.Decimal(5, 2)
  components  Json     // [{ "name": "CGST", "rate": 2.5 }, { "name": "SGST", "rate": 2.5 }] — rates sum to `rate`
  inclusive   Boolean  @default(false)
  isLiquor    Boolean  @default(false) // liquor lines are never discounted
  isActive    Boolean  @default(true)
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
  @@unique([tenantId, code])
  @@map("tax_classes")
}

model Category {
  id           String   @id @default(uuid())
  tenantId     String
  name         String
  sortOrder    Int      @default(0)
  station      String   @default("KITCHEN") // routing key, e.g. "BAR", "KITCHEN", "TANDOOR"
  ticketKind   TicketKind @default(KOT)      // BOT for drinks
  taxClassId   String?  // default for products in this category
  color        String?  // hex for the POS rail
  isActive     Boolean  @default(true)
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt
  @@index([tenantId])
  @@map("categories")
}

// Product gains: categoryId String?, taxClassId String? (overrides category; null = category's, then legacy taxPercentage/global tax),
//                is86 Boolean @default(false), sortOrder Int @default(0), variants ProductVariant[], modifierGroups ProductModifierGroup[]

model ProductVariant {
  id        String   @id @default(uuid())
  productId String
  name      String   // "30 ml", "60 ml", "Bottle", "Shot"
  price     Decimal  @db.Decimal(12, 2)
  sortOrder Int      @default(0)
  isDefault Boolean  @default(false)
  isActive  Boolean  @default(true)
  @@index([productId])
  @@map("product_variants")
}

model ModifierGroup {
  id        String   @id @default(uuid())
  tenantId  String
  name      String   // "How to serve (spirits)"
  minSelect Int      @default(0)
  maxSelect Int      @default(1)
  showOn    String[] @default(["POS"]) // POS, QR, KIOSK
  isActive  Boolean  @default(true)
  options   ModifierOption[]
  @@index([tenantId])
  @@map("modifier_groups")
}

model ModifierOption {
  id         String  @id @default(uuid())
  groupId    String
  name       String  // "With soda"
  priceDelta Decimal @db.Decimal(12, 2) @default(0)
  sortOrder  Int     @default(0)
  isActive   Boolean @default(true)
  @@index([groupId])
  @@map("modifier_options")
}

model ProductModifierGroup {
  productId String
  groupId   String
  sortOrder Int @default(0)
  @@id([productId, groupId])
  @@map("product_modifier_groups")
}

model Combo {
  id         String   @id @default(uuid())
  tenantId   String
  name       String   // "Beer bucket (5)"
  price      Decimal  @db.Decimal(12, 2)
  taxClassId String?
  days       Int[]    @default([0,1,2,3,4,5,6]) // 0 = Sunday
  startTime  String?  // "17:00" outlet local time; null = all day
  endTime    String?  // "23:59"
  isActive   Boolean  @default(true)
  items      ComboItem[]
  @@index([tenantId])
  @@map("combos")
}

model ComboItem {
  id          String  @id @default(uuid())
  comboId     String
  productId   String
  variantId   String?
  quantity    Int     @default(1)
  swapAllowed Boolean @default(false)
  @@index([comboId])
  @@map("combo_items")
}

model PriceRule {           // happy hour
  id          String   @id @default(uuid())
  tenantId    String
  outletId    String?  // null = all outlets
  name        String   // "Happy hour"
  percentOff  Decimal  @db.Decimal(5, 2)
  categoryIds String[] @default([])
  productIds  String[] @default([])
  days        Int[]    @default([0,1,2,3,4,5,6])
  startTime   String   // "17:00"
  endTime     String   // "20:00"
  isActive    Boolean  @default(true)
  @@index([tenantId])
  @@map("price_rules")
}

model Area {                // floor-plan section
  id                 String  @id @default(uuid())
  tenantId           String
  outletId           String
  name               String  // "Rooftop"
  sortOrder          Int     @default(0)
  priceMarkupPercent Decimal @db.Decimal(5, 2) @default(0) // "Rooftop (+10%)"
  isSmoking          Boolean @default(false)
  isActive           Boolean @default(true)
  tables             DiningTable[]
  @@index([outletId])
  @@map("areas")
}

model DiningTable {
  id           String      @id @default(uuid())
  tenantId     String
  outletId     String
  areaId       String
  area         Area        @relation(fields: [areaId], references: [id])
  name         String      // "R4"
  seats        Int         @default(4)
  shape        TableShape  @default(SQUARE)
  posX         Int         @default(0)
  posY         Int         @default(0)
  status       TableStatus @default(FREE)
  mergedIntoId String?     // set on tables merged into another
  isActive     Boolean     @default(true)
  @@unique([outletId, name])
  @@index([outletId])
  @@map("dining_tables")
}

model OutletSettings {
  outletId              String       @id
  serviceChargePercent  Decimal      @db.Decimal(5, 2) @default(0)
  serviceChargeTypes    OrderType[]  @default([DINE_IN])
  roundingMode          RoundingMode @default(NEAREST_1)
  orderPrefix           String       @default("A")
  lastOrderSeq          Int          @default(0)
  invoicePrefix         String       @default("INV")
  countryCode           String       @default("IN")
  updatedAt             DateTime     @updatedAt
  @@map("outlet_settings")
}

// Order gains: orderNumber String? (e.g. "A-1043", @@unique([outletId, orderNumber])), type OrderType @default(DINE_IN),
//   tableId String?, covers Int @default(1), waiterId String?, discountTotal / serviceCharge / tipTotal / roundOff Decimal(12,2) @default(0),
//   taxBreakdown Json?, note String?, offlineId String? @unique, heldAt / billedAt / paidAt / closedAt / voidedAt DateTime?, voidReason String?,
//   dayCloseId String?.  invoiceNumber becomes String? (still @unique) — assigned when the order is PAID. status default becomes OPEN.
// OrderItem gains: variantId String?, variantName String?, seat Int?, status OrderItemStatus @default(NEW), modifiers Json @default("[]")
//   ([{ "groupId", "optionId", "name", "priceDelta" }]), note String?, grossAmount / discountAmount Decimal(12,2) @default(0),
//   happyHourPercent Decimal(5,2)?, taxClassId String?, taxBreakdown Json?, comboId String?, sentAt / voidedAt DateTime?, voidReason String?, createdById String?.
//   Existing `price` = final unit price after markup and happy hour; `taxPercentage`, `taxAmount`, `lineTotal` keep their meaning.
// Payment gains: seat Int?, tipAmount Decimal(12,2) @default(0), tendered Decimal(12,2)?, changeGiven Decimal(12,2)?, reference String?, createdById String?.

model OrderDiscount {
  id           String       @id @default(uuid())
  orderId      String
  type         DiscountType
  value        Decimal      @db.Decimal(12, 2) // percent or ₹
  itemIds      String[]     @default([])       // empty = whole bill (non-liquor)
  amount       Decimal      @db.Decimal(12, 2) // computed
  reason       String
  createdById  String
  approvedById String?
  createdAt    DateTime     @default(now())
  @@index([orderId])
  @@map("order_discounts")
}

model Ticket {
  id             String       @id @default(uuid())
  tenantId       String
  outletId       String
  orderId        String
  kind           TicketKind
  station        String
  seq            Int          // per outlet per business day
  status         TicketStatus @default(QUEUED)
  isCancellation Boolean      @default(false)
  items          Json         // [{ "orderItemId", "name", "variantName", "quantity", "modifiers": ["On the rocks"], "note", "seat" }]
  printerId      String?
  createdById    String
  createdAt      DateTime     @default(now())
  printedAt      DateTime?
  @@index([outletId, createdAt])
  @@index([orderId])
  @@map("tickets")
}

model Printer {
  id               String            @id @default(uuid())
  tenantId         String
  outletId         String
  name             String            // "Main bar BOT"
  connection       PrinterConnection @default(LAN)
  host             String?           // IP for LAN
  port             Int               @default(9100)
  paperWidth       Int               @default(80) // 58 | 80
  copies           Int               @default(1)
  language         String            @default("en") // en | ta
  isReceipt        Boolean           @default(false) // bills, X/Z, cash drawer
  isActive         Boolean           @default(true)
  lastStatus       String?           // READY | PAPER_LOW | OFFLINE
  lastSeenAt       DateTime?
  @@index([outletId])
  @@map("printers")
}

model StationRoute {
  id                String  @id @default(uuid())
  tenantId          String
  outletId          String
  station           String  // matches Category.station
  printerId         String?
  fallbackPrinterId String?
  @@unique([outletId, station])
  @@map("station_routes")
}

model PrintJob {
  id        String         @id @default(uuid())
  tenantId  String
  outletId  String
  printerId String
  kind      PrintJobKind
  payload   Json           // { "lines": [ { "text", "bold"?, "align"?: "left|center|right", "size"?: 1|2 } ], "cut": true, "openDrawer"?: true }
  status    PrintJobStatus @default(QUEUED)
  attempts  Int            @default(0)
  error     String?
  ticketId  String?
  createdAt DateTime       @default(now())
  doneAt    DateTime?
  @@index([outletId, status])
  @@map("print_jobs")
}

model Approval {
  id            String         @id @default(uuid())
  tenantId      String
  outletId      String
  orderId       String?
  type          ApprovalType
  status        ApprovalStatus @default(PENDING)
  requestedById String
  approverId    String?
  payload       Json           // DISCOUNT: { type, value, itemIds, reason } · VOID: { itemIds | "order", reason } · REFUND: { paymentId?, amount, reason } · NO_SALE: { reason }
  reason        String
  createdAt     DateTime       @default(now())
  decidedAt     DateTime?
  expiresAt     DateTime       // createdAt + 15 min
  @@index([outletId, status])
  @@map("approvals")
}

model DayClose {
  id           String       @id @default(uuid())
  tenantId     String
  outletId     String
  kind         DayCloseKind
  businessDate DateTime     @db.Date
  totals       Json         // see 1.6
  cashCounted  Decimal?     @db.Decimal(12, 2)
  cashExpected Decimal?     @db.Decimal(12, 2)
  createdById  String
  createdAt    DateTime     @default(now())
  @@index([outletId, businessDate])
  @@map("day_closes")
}
```

Add all new tenant-owned models (`TaxClass, Category, ModifierGroup, Combo, PriceRule, Area, DiningTable, Ticket, Printer, StationRoute, PrintJob, Approval, DayClose`) to `TENANT_MODELS` in `common/tenancy/tenant-scope.extension.ts` and to the loose-create list in `prisma/prisma.service.ts`. Add relations (`@relation`) where obvious (FKs) — keep the field names above.

### 1.3 Pricing engine (owned by P2-A) — `backend/src/common/pricing/pricing.engine.ts`

Pure TypeScript, no Nest/Prisma calls (uses `Prisma.Decimal` only). Every order mutation re-prices the whole order with it; the frontend shows the server's numbers.

```ts
export interface PricingTaxClass { id: string; rate: Decimal; components: { name: string; rate: number }[]; inclusive: boolean; isLiquor: boolean }
export interface PricingLineInput {
  id: string;                 // order item id (or temp id)
  baseUnitPrice: Decimal;     // variant price, else product price, else combo price
  modifiersDelta: Decimal;    // sum of option priceDelta
  quantity: number;
  taxClass: PricingTaxClass;
  areaMarkupPercent: Decimal; // 0 if none / not dine-in
  happyHourPercent: Decimal | null;
  voided: boolean;            // voided lines are priced at 0 and excluded
}
export interface PricingDiscountInput { type: 'PERCENT' | 'FLAT'; value: Decimal; itemIds: string[] } // itemIds empty = whole bill
export interface PricingInput {
  lines: PricingLineInput[];
  discounts: PricingDiscountInput[];
  serviceChargePercent: Decimal; // 0 when the order type isn't in serviceChargeTypes
  roundingMode: 'NONE' | 'NEAREST_1';
}
export interface PricedLine { id: string; unitPrice: Decimal; gross: Decimal; discount: Decimal; net: Decimal; tax: Decimal; taxBreakdown: { name: string; rate: number; amount: Decimal }[]; total: Decimal }
export interface PricingResult {
  lines: PricedLine[];
  subtotal: Decimal;       // Σ gross (ex-tax)
  discountTotal: Decimal;
  netSubtotal: Decimal;    // subtotal − discountTotal
  serviceCharge: Decimal;
  taxTotal: Decimal;
  taxBreakdown: { name: string; rate: number; amount: Decimal }[]; // grouped by component name + rate
  roundOff: Decimal;
  grandTotal: Decimal;
  discountableBase: Decimal; // Σ net of non-liquor lines before discounts (for % validation)
}
export function priceOrder(input: PricingInput): PricingResult;
export function isWithinSchedule(now: Date, timeZone: string, days: number[], start: string | null, end: string | null): boolean;
```

Rules (in order, each step `round2`):
1. `unitPrice = (baseUnitPrice + modifiersDelta) × (1 + areaMarkupPercent/100)`, then `× (1 − happyHourPercent/100)` if set.
2. For an **inclusive** tax class, the unit price includes tax: `exUnit = unitPrice / (1 + rate/100)`. Gross is always ex-tax: `gross = exUnit × quantity` (exclusive classes: `unitPrice × quantity`).
3. Discounts apply only to **non-liquor** lines. A discount whose `itemIds` include a liquor line throws `PricingError('LIQUOR_DISCOUNT_NOT_ALLOWED')`. PERCENT: each eligible line `discount += gross × value/100`. FLAT: split across eligible lines in proportion to gross; put the rounding remainder on the largest line. A line's discount never exceeds its gross.
4. `net = gross − discount`; `tax = net × rate/100`; component amounts = `net × component.rate/100`, with the rounding remainder on the last component so components sum to `tax`; `total = net + tax`.
5. `serviceCharge = netSubtotal × serviceChargePercent/100` (not taxed in Phase 2 — flag for the CA).
6. `preRound = netSubtotal + serviceCharge + taxTotal`; NEAREST_1 rounds half-up to whole rupees, `roundOff = rounded − preRound`; `grandTotal = rounded`.
7. Tips are not part of `grandTotal` (stored on payments, `Order.tipTotal`).

`isWithinSchedule` handles windows that cross midnight (`22:00`–`02:00`) and uses `Intl.DateTimeFormat` with the outlet's `timezone`.

Tests (`pricing.engine.spec.ts`): exclusive + inclusive, happy hour, area markup, % and flat discounts with remainder, liquor exclusion error, voided line, service charge, rounding, multi-component breakdown sums, cross-midnight schedule. Include one test reproducing the POS board's ticket (lager 2×₹300, wings ₹350, mojito ₹350 −30%, single malt 60 ml ₹500 + soda ₹40; service 5%; GST 5% food/soft, VAT 20% liquor) and assert internal consistency (Σ lines + service + tax + roundOff = grand).

### 1.4 Backend APIs

All under `/api/v1`, outlet = `auth.outletId` unless stated. Errors: `{ code }` values listed per endpoint.

**Menu & settings (P2-B)**

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/menu/pos` | `sales.orders.take VIEW` | Everything the POS needs in one call: `{ categories: [{id,name,color,sortOrder}], products: [{id,name,categoryId,price,is86,imageUrl,taxClassId,variants:[{id,name,price,isDefault}],modifierGroupIds:[]}], modifierGroups: [{id,name,minSelect,maxSelect,options:[{id,name,priceDelta}]}], combos: [{id,name,price,items:[...],availableNow}], priceRules: [{id,name,percentOff,categoryIds,productIds,activeNow,endsAt}], taxClasses: [{id,code,name,rate,isLiquor,inclusive}], settings: {serviceChargePercent, serviceChargeTypes, roundingMode} }`. Inactive items excluded. |
| GET/POST/PATCH/DELETE | `/categories`, `/categories/:id` | read `menu.edit VIEW`, write `menu.edit EDIT` | delete = soft (`isActive=false`); 409 `CATEGORY_IN_USE` if active products |
| PATCH | `/products/:id` (extend existing DTO) | `menu.edit EDIT` | accepts `categoryId`, `taxClassId`, `sortOrder` |
| PUT | `/products/:id/variants` | `menu.edit EDIT` | `{ items: [{ id?, name, price, isDefault, sortOrder }] }` replaces; exactly one default if any |
| PUT | `/products/:id/modifier-groups` | `menu.edit EDIT` | `{ groupIds: [] }` |
| POST | `/products/:id/86` | `menu.mark86 EDIT` | `{ is86: boolean }` — also emits a notification to the outlet |
| CRUD | `/modifier-groups` (+ nested `options` in body) | `menu.edit` | PUT replaces options |
| CRUD | `/combos` | `menu.edit` | body includes `items` |
| CRUD | `/price-rules` | `menu.edit` | |
| CRUD | `/tax-classes` | `admin.settings` | delete → 409 `TAX_CLASS_IN_USE` if active products/categories use it; past orders keep snapshots |
| GET/PUT | `/outlet-settings` | read `admin.settings VIEW`, write `admin.settings EDIT` | `{ serviceChargePercent, serviceChargeTypes, roundingMode, orderPrefix, invoicePrefix, countryCode }` |
| CRUD | `/areas`, `/tables` | read `sales.orders.take VIEW`, write `admin.settings EDIT` | `GET /tables` returns live view: `[{ id, name, areaId, seats, shape, posX, posY, status, mergedIntoId, order: { id, orderNumber, covers, grandTotal, openedAt, waiterName } | null }]` |
| PATCH | `/tables/:id/status` | `sales.orders.take EDIT` | `{ status: FREE | CLEANING | RESERVED }` (OCCUPIED / BILL_PRINTED are set by orders) |
| CRUD | `/printers` | `admin.settings` | |
| POST | `/printers/:id/test` | `admin.settings EDIT` | queues a TEST print job |
| GET/PUT | `/station-routes` | `admin.settings` | `{ items: [{ station, printerId, fallbackPrinterId }] }` |
| GET | `/print-jobs/next` | public + `X-Device-Key` (device type PRINTER or POS_TABLET) | up to 10 QUEUED jobs for the device's outlet, marks them SENT, returns `[{ id, kind, printer: { host, port, paperWidth, copies }, payload }]` |
| POST | `/print-jobs/:id/result` | public + `X-Device-Key` | `{ ok: boolean, error?: string, printerStatus?: 'READY'|'PAPER_LOW'|'OFFLINE' }` → DONE or (attempts < 3 → QUEUED, else FAILED + notification "Printer X failed"); if a ticket job fails and the route has a fallback printer, requeue there |

`PrintService` (P2-B, `modules/printing/print.service.ts`) is used by P2-C: `queueTicket(ticket)`, `queueBill(orderId, { copies })`, `queueReport(dayCloseId)`, `openDrawer(outletId, reason)`. It renders `payload.lines` (header with outlet name, order number, table, staff, time; items with modifiers indented; totals with tax breakdown; footer) for 32 columns (58 mm) or 48 columns (80 mm).

**Print agent (P2-B)** — `print-agent/` at repo root: tiny Node 20 TypeScript app (no runtime deps beyond Node; `package.json` with `typescript` dev dep), `src/index.ts` polls `GET /print-jobs/next` every 2 s with `X-Device-Key`, converts `payload` to ESC/POS bytes (init `ESC @`, bold `ESC E n`, align `ESC a n`, size `GS ! n`, cut `GS V 66 0`, drawer `ESC p 0 25 250`), writes to `host:port` over TCP (`net.Socket`, 5 s timeout), posts the result. Config via env `API_BASE_URL`, `DEVICE_KEY`. README with setup steps (register device type PRINTER in Settings → Devices).

**Orders, payments, approvals, reports (P2-C)**

| Method | Path | Permission | Body → Response / errors |
|---|---|---|---|
| POST | `/orders` | `sales.orders.take EDIT` | `{ type, tableId?, covers?, waiterId?, note?, offlineId?, items?: [AddItem] }` → `OrderView`. Idempotent on `offlineId` (returns the existing order). Dine-in requires `tableId`; table must be FREE/RESERVED → becomes OCCUPIED. 409 `TABLE_OCCUPIED`. Allocates `orderNumber` = `${orderPrefix}-${++lastOrderSeq}` in a transaction. |
| GET | `/orders/open` | `sales.orders.take VIEW` | open orders (OPEN/SENT/BILLED) of the outlet, light list |
| GET | `/orders/:id` | `sales.orders.take VIEW` | `OrderView` |
| POST | `/orders/:id/items` | `sales.orders.take EDIT` | `{ items: [AddItem] }` → `OrderView`; 400 `ITEM_86`, `MODIFIER_RULES` (min/max), `COMBO_UNAVAILABLE` |
| PATCH | `/orders/:id/items/:itemId` | `sales.orders.take EDIT` | `{ quantity?, seat?, note?, modifiers? }` only while item `NEW`; 409 `ITEM_ALREADY_SENT` |
| DELETE | `/orders/:id/items/:itemId` | `sales.orders.take EDIT` | only `NEW` items (no approval needed); sent items must be voided |
| POST | `/orders/:id/send` | `sales.orders.take EDIT` | sends all `NEW` items: groups by category `station`/`ticketKind`, creates one `Ticket` per station, queues print jobs, items → SENT, order → SENT. → `{ order: OrderView, tickets: [{ id, kind, station, seq }] }`. 400 `NOTHING_TO_SEND` |
| POST | `/orders/:id/hold` / `/unhold` | `sales.orders.take EDIT` | sets/clears `heldAt` |
| POST | `/orders/:id/discounts` | `sales.discount.give ≥ REQUEST` | `{ type, value, itemIds, reason, approvalId? }`. Allowed directly if level EDIT, APPROVE, or LIMITED with percent-equivalent ≤ limit. Otherwise needs `approvalId` of an APPROVED `DISCOUNT` approval with the same payload, else 403 `APPROVAL_REQUIRED` with `details: { limit }`. 400 `LIQUOR_DISCOUNT_NOT_ALLOWED`. |
| DELETE | `/orders/:id/discounts/:discountId` | `sales.discount.give EDIT` | |
| POST | `/orders/:id/void-items` | `sales.void ≥ REQUEST` | `{ itemIds, reason, approvalId? }`. APPROVE/EDIT → direct; else needs approval (403 `APPROVAL_REQUIRED`). SENT items → cancellation ticket at their station + audit log entry "wastage: <reason>". |
| POST | `/orders/:id/void` | `sales.void ≥ REQUEST` | whole order, same approval rule; only if no payments; order → VOID, table → FREE |
| POST | `/orders/:id/move` | `sales.orders.take EDIT` | `{ toTableId }` → order moves; old table FREE (or CLEANING), new OCCUPIED; 409 `TABLE_OCCUPIED`; 400 `TABLE_TOO_SMALL` with `details: { seats, covers }` unless `force: true`; audit log |
| POST | `/orders/:id/merge` | `sales.orders.take EDIT` | `{ fromOrderId }` → items and discounts of `fromOrderId` move into this order, `fromOrder` VOID with reason "merged into A-…", its table FREE; audit log |
| POST | `/orders/:id/transfer-items` | `sales.orders.take EDIT` | `{ itemIds, toOrderId? , toTableId? }` (creates an order on the target table if needed) |
| POST | `/orders/:id/bill` | `sales.payments.take VIEW` | queues bill print (receipt printer), order → BILLED, table → BILL_PRINTED. `{ copies? }` |
| GET | `/orders/:id/split` | `sales.payments.take VIEW` | `?mode=EQUAL&parts=3` or `mode=SEAT` or `mode=ITEMS&assign=<itemId>:<seat>,…` → `{ shares: [{ label: "Seat 2", seat: 2, itemIds, amount, paid, due }] }`. Amounts come from the priced lines + proportional service charge and round-off; the last share takes the remainder so shares sum to `grandTotal`. Shared items (same item on several seats via `assign`) split their total equally. |
| POST | `/orders/:id/payments` | `sales.payments.take EDIT` | `{ payments: [{ method, amount, tendered?, reference?, seat? }], tipAmount?, completeSeat? }` (split tender in one call). Cash: `changeGiven = tendered − amount` (≥ 0). Overpay → 400 `PAYMENT_EXCEEDS_DUE` with `details: { due }`. When total paid ≥ grand: order → PAID, `paidAt`, `invoiceNumber` = `InvoiceNumberService.next(tx, profile, outletSettings.invoicePrefix, resetPeriod)` using the outlet's `countryCode` profile, an `Invoice` row is created (reuse `InvoiceService` logic or its repository) with the tax breakdown; dine-in table → CLEANING; takeaway/bar counter → order CLOSED. If any cash: queue `openDrawer`. → `{ order: OrderView, change: "30.00" }` |
| POST | `/orders/:id/close` | `sales.payments.take EDIT` | PAID → CLOSED, table → CLEANING (if not already) |
| POST | `/orders/:id/refund` | `sales.payments.take EDIT` + approval rule like void (`REFUND`) | `{ amount, reason, paymentId?, approvalId? }` → negative payment row (status REFUNDED); full refund → order REFUNDED |
| POST | `/approvals` | `sales.orders.take EDIT` | `{ type, orderId?, payload, reason }` → approval PENDING (expires in 15 min) + `Notification` (type `approval`, `permissionKey` per type: DISCOUNT→`sales.discount.give`, VOID→`sales.void`, REFUND→`sales.void`, NO_SALE→`sales.payments.take`) for the outlet |
| POST | `/approvals/:id/decide` | approver with ≥ APPROVE on that key (or EDIT) | `{ decision: APPROVED | DECLINED }` |
| POST | `/approvals/pin` | `sales.orders.take EDIT` | manager at the same device: `{ type, orderId?, payload, reason, managerUserId, pin }` → creates and approves in one step if that manager has ≥ APPROVE; wrong PIN uses the Phase 1 PIN lockout (401 `PIN_INVALID` / 423 `PIN_LOCKED`); 403 `APPROVER_NOT_ALLOWED` |
| GET | `/approvals/:id` | auth | polling target for "Waiting for approval…" |
| GET | `/approvals?status=PENDING` | auth | for the notifications panel |
| GET | `/reports/x` | `reports.view LIMITED` | live shift totals for today (outlet business date) — totals shape 1.6, not saved |
| POST | `/reports/z` | `reports.view EDIT` | `{ cashCounted }` → creates `DayClose(kind Z)` for the business date, links today's PAID/CLOSED/VOID orders (`dayCloseId`), queues the report print; 409 `DAY_ALREADY_CLOSED`; 409 `OPEN_ORDERS_EXIST` with `details: { count }` unless `force: true` |
| GET | `/reports/day-closes` | `reports.view LIMITED` | list |
| POST | `/cash-drawer/open` | `sales.payments.take EDIT` | "No sale": `{ reason }`, needs approval (`NO_SALE`) unless EDIT; audit log |

`AddItem = { productId? , variantId?, comboId?, quantity, seat?, note?, modifierOptionIds?: string[] }` (exactly one of productId or comboId).

`OrderView`:
```json
{ "id", "orderNumber", "type", "status", "table": { "id", "name", "areaName" } | null, "covers", "waiter": { "id", "name" } | null,
  "openedAt", "heldAt", "billedAt", "paidAt", "note",
  "items": [ { "id", "productId", "comboId", "name", "variantName", "seat", "quantity", "status", "modifiers": [{ "optionId", "name", "priceDelta" }], "note",
               "unitPrice", "gross", "discount", "net", "tax", "total", "happyHourPercent", "isLiquor", "ticketKind", "station", "sentAt" } ],
  "discounts": [ { "id", "type", "value", "itemIds", "amount", "reason", "approvedBy" } ],
  "payments": [ { "id", "method", "amount", "tipAmount", "tendered", "changeGiven", "reference", "seat", "status", "createdAt" } ],
  "totals": { "subtotal", "discountTotal", "netSubtotal", "serviceCharge", "taxTotal", "taxBreakdown": [{ "name", "rate", "amount" }], "roundOff", "grandTotal", "paid", "due", "tipTotal" },
  "invoiceNumber": null }
```
All money fields are strings with 2 decimals.

**Business date:** the outlet's local date (outlet `timezone`) with a 5 am cut-off (orders before 5 am belong to the previous day). Helper `businessDate(now, timezone)` in `common/pricing/business-date.ts` (P2-A).

### 1.5 Existing endpoints

`POST /orders` with the legacy body `{ items: [{ productId, quantity }] }` (old billing screen) keeps working: P2-C treats it as `type: TAKEAWAY`, prices with the engine, and returns the new `OrderView` plus legacy fields `invoiceNumber`, `subtotal`, `taxAmount`, `grandTotal`. `POST /payments` (legacy) keeps working by delegating to the new payments service.

### 1.6 Day-close totals JSON

`{ "businessDate", "orders": { "count", "paid", "void", "open" }, "gross", "discounts", "serviceCharge", "tax": [{ "name", "rate", "amount" }], "roundOff", "net", "tips", "byPayment": [{ "method", "count", "amount" }], "byType": [{ "type", "count", "amount" }], "byCategory": [{ "categoryId", "name", "quantity", "amount" }], "voids": { "count", "amount" }, "refunds": { "count", "amount" }, "discountsByStaff": [{ "userId", "name", "amount" }], "cashExpected" }`

### 1.7 Frontend contracts

**Data layer (P2-D owns `frontend/lib/features/pos/data/**`, used by P2-E too):**
- `pos_models.dart`: `PosMenu`, `PosCategory`, `PosProduct`, `PosVariant`, `PosModifierGroup`, `PosModifierOption`, `PosCombo`, `PosPriceRule`, `OrderView`, `OrderItemView`, `OrderTotals`, `PaymentView`, `DiscountView`, `SplitShare`, `TableView`, `ApprovalView`, `DayCloseTotals` — `fromJson` for each; money as `String` + `num get amount`.
- `pos_repository.dart`: `PosRepository` with one method per endpoint in 1.4 (orders, approvals, tables live view, reports), returning the models; errors as Phase 1 `ApiError`. Provider `posRepositoryProvider`.
- `offline_queue.dart`: `OfflineOrderQueue` (Hive box `offline_orders`) storing `CreateOrder` requests with an `offlineId` (uuid v4 generated locally without packages: 16 random bytes from `Random.secure()`), `flush()` on reconnect / every 30 s; UI shows "Offline — 2 orders will sync".

**Screens and routes** (P2-E owns `core/router/app_router.dart` and `core/shell/nav_registry.dart` changes):

| Route | Class | File | Owner |
|---|---|---|---|
| `/pos` | `PosScreen` (no order selected → floor/quick start: pick order type; dine-in shows tables grid) | `features/pos/presentation/pos_screen.dart` | P2-D |
| `/pos/:orderId` | `PosScreen(orderId:)` | same | P2-D |
| `/pos/:orderId/pay` | `PayScreen(orderId:)` | `features/pos/presentation/pay_screen.dart` | P2-D |
| — (dialogs) | `showDiscountDialog`, `showVoidDialog`, `showTransferDialog`, `showModifierSheet`, `showManagerPinDialog` | `features/pos/presentation/dialogs/*.dart` | P2-D |
| `/floor` | `FloorPlanScreen` | `features/floor/presentation/floor_plan_screen.dart` | P2-E |
| `/menu` | `ProductsScreen` stays; add tabs/links to editors | existing | P2-E |
| `/menu/categories` | `CategoriesScreen` | `features/menu/presentation/categories_screen.dart` | P2-E |
| `/menu/products/:id` | `ProductEditorScreen` (details, category, tax class, variants, modifier groups, 86) | `features/menu/presentation/product_editor_screen.dart` | P2-E |
| `/menu/modifiers` | `ModifierGroupsScreen` | `features/menu/presentation/modifier_groups_screen.dart` | P2-E |
| `/menu/combos` | `CombosScreen` | `features/menu/presentation/combos_screen.dart` | P2-E |
| `/menu/happy-hours` | `PriceRulesScreen` | `features/menu/presentation/price_rules_screen.dart` | P2-E |
| `/orders` | `OrdersScreen` (replaces `OrderHistoryScreen` in the router; filters by status/type/payment/date, detail drawer, reprint, refund/void with manager PIN using `showManagerPinDialog` from P2-D) | `features/orders/presentation/orders_screen.dart` | P2-E |
| `/settings/tax` | `TaxSettingsScreen` → rework into tabs: Tax rules (tax classes), Service charge & rounding (outlet settings), Invoice numbering (prefixes) — keep the legacy global-tax card | `features/tax/presentation/tax_settings_screen.dart` | P2-E |
| `/settings/hardware` | `HardwareScreen` (printers table with status + Test, Add printer dialog with LAN/USB/Bluetooth + IP validation + "Can't reach this printer" error from failed test job, ticket routing table per station) | `features/hardware/presentation/hardware_screen.dart` | P2-E |
| `/settings/floor` | `FloorSetupScreen` (areas + tables CRUD, drag to position on a grid) | `features/floor/presentation/floor_setup_screen.dart` | P2-E |
| `/reports/day-close` | `DayCloseScreen` (X report live view, Z report with cash counted → expected vs counted variance, list of past closes) | `features/reports/presentation/day_close_screen.dart` | P2-E |

Nav registry additions: Floor plan `/floor` (`sales.orders.take VIEW`, group Sales), Day close `/reports/day-close` (`reports.view LIMITED`, group Sales), Hardware `/settings/hardware` (`admin.settings VIEW`), Floor setup `/settings/floor` (`admin.settings VIEW`). With the default matrix the Bartender now sees **6** items (POS billing, Orders, Floor plan, Menu & products, Stock count, My shifts); update `test/shell/nav_filter_test.dart` to expect that (P2-E).

**POS screen behaviour (P2-D, match the POS and TabletPOS boards):** top bar with order-type tabs (Dine-in, Bar counter, Takeaway, Delivery), active happy-hour banner ("Happy hour ends 8:00 pm" from `priceRules.endsAt`), table + covers + waiter chip; left category rail (Favourites = top 12 by recent use, stored locally); product grid with variant chips on each card (tap chip = add that variant; tap card = default variant), 86'd items greyed with "Out of stock"; search box; modifier sheet when the product has groups (enforces min/max, shows price deltas, seat picker 1..covers, note); right ticket panel listing items with seat, modifiers, status chip (New / KOT sent / BOT sent), happy-hour tag, qty stepper for NEW items; totals block (subtotal, service charge %, tax line "GST (food) · VAT (liquor)", total); action row Hold · Split · Discount · Transfer · Void item · Print bill · **Send KOT/BOT** · **Pay ₹X**. Tablet ≤ 1024 px: ticket panel becomes a bottom sheet. All prices displayed come from `OrderView` (server), except the optimistic line added before the server replies (show a small spinner on that line).

**Pay screen (P2-D, POSPay board):** modes One bill / Split equally (parts stepper) / By seat / By item (assign items to seats by tapping); share list with paid/due; tip chips None / 5% / 10% / Custom; tender list (Cash, UPI with reference field, Card terminal "Ready"); cash keypad with quick amounts (₹500 ₹1,000 ₹2,000 Exact) and "Change to give"; "Complete seat N" / "Complete payment"; note "Cash drawer opens on Complete". Offline: payments can't be taken offline (show reason).

**Approval dialogs (P2-D, POSApprove board):** discount (Percent/Flat, quick 5/10/20/Other, apply to whole bill — "food only, liquor excluded by law" — or selected items, reason chips), shows "20% is above your 10% limit. A manager must approve." with two options: "Manager enters PIN here" (`showManagerPinDialog` → `/approvals/pin`, shows Phase 1 PIN errors) or "Send to manager's phone" (`POST /approvals` then poll `GET /approvals/:id` every 3 s; "Sent to Priya. Waiting for approval… You can keep taking orders."). Void dialog (select items, required reason chips, warning when an item was already sent: "A cancellation ticket will print there, and the stock is logged as wastage."). Move/merge dialog (whole table / some items / merge, table grid with statuses, seat-size warning "R5 has 2 seats but R4 has 4 guests…").

---

## 2. Workstreams

### P2-A — Data model, migration, pricing engine, seed (backend)
**Owns:** `backend/prisma/**`, `backend/src/common/pricing/**`, `backend/src/common/tenancy/tenant-scope.extension.ts` (TENANT_MODELS only), `backend/src/prisma/prisma.service.ts` (loose-create list only).
1. Schema per 1.2 (with relations). Keep existing field names.
2. Migration `backend/prisma/migrations/20261125130000_phase2_pos_core/migration.sql`, hand-written in the style of the existing migrations: new enums/tables/indexes/FKs; `ALTER TYPE "OrderStatus" ADD VALUE 'OPEN'` etc. (do **not** use the new enum values in the same migration — set the column default to `'OPEN'` in a **second** migration `20261125130100_phase2_order_default/migration.sql`); `orders.invoiceNumber DROP NOT NULL`; new columns with defaults; `outlet_settings` row for every existing outlet; default tax classes for every tenant (`GST5` 5% CGST 2.5 + SGST 2.5; `VAT_LIQUOR` 20% VAT, isLiquor; `GST18` 18% CGST 9 + SGST 9).
3. `pricing.engine.ts`, `pricing.errors.ts` (`PricingError` with `code`), `business-date.ts`, and specs per 1.3.
4. Seed (`seed.ts`, idempotent): demo bar menu for the default tenant matching the POS board — categories Spirits/Beer & draught/Cocktails/Wine/Mocktails & soft (station BAR, BOT), Bar bites/Mains/Desserts (KITCHEN, KOT); products with variants (House Whisky 30 ml ₹180 / 60 ml ₹340 / Bottle ₹4,800; Single Malt 12Y 30 ml ₹280 / 60 ml ₹540; Premium Lager 650 ml ₹300; Classic Mojito ₹350; Chicken Wings (8 pc) ₹350; …); modifier group "How to serve (spirits)" (exactly 1: On the rocks, Neat, With soda +₹40, With water) linked to spirits; Happy hour 17:00–20:00 30% off Cocktails; areas Indoor/Rooftop (+10%)/Bar counter with tables R1–R9, T1–T4, Bar 1–10; outlet settings service charge 5% for dine-in; a receipt printer "Counter receipt" 192.168.1.30, "Main bar BOT" .31, "Kitchen KOT" .32 and station routes BAR→bar, KITCHEN→kitchen. Leave Phase 1 seed data intact.
5. Report.

### P2-B — Menu, settings, floor, hardware APIs + print service + print agent
**Owns:** new `backend/src/modules/{menu,categories,modifiers,combos,price-rules,tax-classes,outlet-settings,floor,printing}/**`, edits to `backend/src/modules/products/**` (variants, modifier groups, 86, category/tax class fields), `backend/src/app.module.ts` (register your modules **and** P2-C's modules: `orders` stays, new `approvals`, `day-close`, `cash-drawer` — import paths `./modules/approvals/approvals.module`, `./modules/day-close/day-close.module`, `./modules/cash-drawer/cash-drawer.module`), `print-agent/**`, `docs/API.md` (menu/settings/hardware section).
Implement the P2-B rows of 1.4, `PrintService` (exported from `PrintingModule`, `@Global()`), and the print agent. Tests: print rendering (column widths, totals block), station route fallback, `GET /menu/pos` filters inactive/86 flags, variants single-default rule.

### P2-C — Orders, payments, approvals, day close (backend)
**Owns:** `backend/src/modules/orders/**`, `backend/src/modules/payments/**`, new `backend/src/modules/{approvals,day-close,cash-drawer}/**`, `backend/src/modules/reports/**` (X/Z only; keep existing dashboard endpoints), and the order/invoice integration points inside `backend/src/modules/invoice/**` (only add an `issueForOrder(tx, orderId)` method if needed; don't change existing endpoints), `docs/API.md` (orders/payments/approvals/reports section — coordinate by adding your own `## Orders (Phase 2)` section).
Implement the P2-C rows of 1.4, 1.5, 1.6 using `priceOrder` (P2-A) and `PrintService` (P2-B: `import { PrintService } from '../printing/print.service'`). All mutations in a Prisma transaction; re-price and persist line + order totals on every change; record `AuditLog` rows for voids, moves, merges, refunds, discounts approved, no-sale. Tests: order lifecycle happy path, send groups tickets by station, discount limit → APPROVAL_REQUIRED and success with approval, liquor discount refused, void of sent item creates cancellation ticket, split shares sum to grand total (equal/seat/items with shared item), split tender with change, overpay refused, invoice number allocated once on PAID, Z close refuses open orders and second close.

### P2-D — POS, pay and approval UI + data layer + offline queue (frontend)
**Owns:** `frontend/lib/features/pos/**`, `frontend/test/pos/**`. Delete `frontend/lib/features/billing/**` at the end and list it in your report (P2-E updates the router).
Implement 1.7 data layer and the POS/Pay/dialog behaviour. Tests: `OrderView.fromJson`, split share display, modifier sheet min/max validation, offline queue stores and flushes (mock repository).

### P2-E — Back-office screens, router, nav (frontend)
**Owns:** `frontend/lib/features/{floor,menu,orders,tax,hardware,reports}/**` (new and existing), `frontend/lib/features/products/presentation/products_screen.dart` (links to editors only), `frontend/lib/core/router/app_router.dart`, `frontend/lib/core/shell/nav_registry.dart`, `frontend/test/shell/nav_filter_test.dart`, `frontend/test/backoffice/**`.
Implement the P2-E screens in 1.7, using `PosRepository`/models from P2-D for orders/tables/reports and your own repositories (`features/<feature>/data/*_repository.dart`) for menu/settings/hardware APIs. Route `/pos`, `/pos/:orderId`, `/pos/:orderId/pay` to P2-D's classes; remove the billing routes; `/billing` redirects to `/pos`. Tests: nav filter (bartender 6 items, admin all), floor plan status colours + labels, tax class components must sum to rate (form validation).

---

## 3. Integration (planner)
Cross-check contracts; resolve report requests; check no leftover imports of `features/billing`; verify migrations vs schema; update `docs/phase-1/INTEGRATION.md` → add `docs/phase-2/INTEGRATION.md` with the pilot test script (section header exit test) and known gaps; commit and push to the PR branch.
