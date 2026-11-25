# API Specification

Base URL: `/api/v1` · Auth: `Authorization: Bearer <accessToken>` · Docs: `/api/docs`

All list endpoints accept `?page=1&limit=20&search=<q>` and return:

```json
{ "data": [ ... ], "meta": { "page": 1, "limit": 20, "total": 0, "totalPages": 0 } }
```

## Session payload (Phase 1)

Returned by every successful login (password, OAuth, select-outlet, switch-outlet, PIN login) and by `GET /auth/me` (without tokens):

```json
{
  "accessToken": "…", "refreshToken": "…",
  "user": { "id": "…", "username": "priya", "displayName": "Priya", "email": "…", "features": [] },
  "tenant": { "id": "…", "name": "Your Venue" },
  "outlet": { "id": "…", "name": "Main outlet", "code": "MAIN" },
  "persona": { "id": "…", "key": "manager", "name": "Manager", "homeRoute": "/dashboard" },
  "permissions": { "menu.edit": { "level": "EDIT", "limit": null }, "sales.discount.give": { "level": "LIMITED", "limit": 30 } },
  "outlets": [ { "id": "…", "name": "Main outlet", "code": "MAIN", "persona": { "key": "manager", "name": "Manager" }, "isDefault": true } ],
  "role": "ADMIN"
}
```

`permissions` holds every catalog key (`NONE` when not granted). `role` is legacy: `ADMIN` for the admin persona, `KIOSK` for the kiosk persona, otherwise `USER`. `user.features` is deprecated and goes with the feature-grant tables in Phase 2.

When a user has more than one outlet and none (or several) is default, password login returns instead:

```json
{ "needsOutlet": true, "selectionToken": "…", "outlets": [ … ] }
```

## Auth
| Method | Path | Auth | Body → Response / Notes |
|--------|------|------|-------------------------|
| POST | `/auth/login` | public | `{ username, password }` → session, or `needsOutlet` (see above). 401 `INVALID_CREDENTIALS`; 403 `NO_OUTLET_ACCESS` when the user has no outlet |
| POST | `/auth/select-outlet` | public | `{ selectionToken, outletId }` → session. Token lives 5 minutes. 401 `SELECTION_EXPIRED` |
| POST | `/auth/switch-outlet` | auth | `{ outletId }` → session with new tokens. 403 `NO_OUTLET_ACCESS` |
| POST | `/auth/refresh` | public | `{ refreshToken }` → `{ accessToken }` (keeps tenant, outlet and persona claims) |
| POST | `/auth/logout` | auth | bumps `tokenVersion`, revoking all refresh tokens → `{ success: true }` |
| GET | `/auth/me` | auth | session without tokens |
| POST | `/auth/forgot-password` | public | `{ usernameOrEmail }` → always `{ success: true }`. Reset link expires in 30 minutes. Phase 1 logs the link (`APP_BASE_URL/reset-password?token=…`) |
| POST | `/auth/reset-password` | public | `{ token, newPassword }` (8+ characters, a letter and a digit) → `{ success: true }`. Bumps `tokenVersion`. 400 `RESET_TOKEN_INVALID` |
| GET | `/auth/pin/staff` | public + `X-Device-Key` | → `{ outlet: { id, name }, staff: [ { userId, displayName, personaName } ] }`. 401 `DEVICE_INVALID` |
| POST | `/auth/pin/login` | public + `X-Device-Key` | `{ userId, pin }` (4 digits) → session for the device's outlet. 401 `PIN_INVALID` with `details.attemptsLeft`. After 3 wrong PINs: 423 `PIN_LOCKED` with `details.lockedUntil` (5 minutes). 403 `NO_OUTLET_ACCESS` when the user is not a PIN persona at that outlet |
| POST | `/auth/login-methods/google/token` | public | `{ idToken }` → same session payload as password login |

Access tokens carry `{ sub, username, tenantId, outletId, personaId, personaKey, tokenVersion }`. On every request the live user and outlet assignment are checked, so removing an outlet takes effect immediately.

## Permissions and personas
Levels, lowest to highest: `NONE < VIEW < REQUEST < LIMITED < APPROVE < EDIT`. A route marked `@Can(key, min)` needs the persona to grant `key` at `min` or above.

| Method | Path | Permission | Body → Response / Notes |
|--------|------|------------|-------------------------|
| GET | `/permissions/catalog` | `admin.users` VIEW | `[ { key, group, label, description, limitUnit, sortOrder } ]` |
| GET | `/personas` | `admin.users` VIEW | `[ { id, key, name, description, homeRoute, loginMethod, isSystem, userCount } ]` |
| POST | `/personas` | `admin.users` EDIT | `{ name, copyFromId? }` → persona. Key is a slug of the name. Copying a matrix cannot grant more than the caller holds (403 `PERMISSION_DENIED`) |
| PATCH | `/personas/:id` | `admin.users` EDIT | `{ name?, description?, homeRoute?, loginMethod? }`. 403 `PERSONA_SYSTEM` for the admin persona |
| DELETE | `/personas/:id` | `admin.users` EDIT | 409 `PERSONA_IN_USE` (with `details.userCount`) while users are assigned. 403 `PERSONA_SYSTEM` |
| GET | `/personas/:id/permissions` | `admin.users` VIEW | `[ { key, level, limit } ]` for every catalog key |
| PUT | `/personas/:id/permissions` | `admin.users` EDIT | `{ items: [ { key, level, limit? } ] }`, a full replacement; keys left out become NONE. 400 `LIMIT_NOT_SUPPORTED` when `limit` is set on a key without a limit unit. 400 `UNKNOWN_PERMISSION`. 403 `PERMISSION_DENIED` when a level is above the caller's own. 403 `PERSONA_SYSTEM` |

## Outlets
| Method | Path | Permission | Body → Response / Notes |
|--------|------|------------|-------------------------|
| GET | `/outlets` | auth | all tenant outlets with `admin.settings` VIEW, otherwise only the caller's outlets |
| POST | `/outlets` | `admin.settings` EDIT | `{ name, code, address?, timezone? }`. 409 `OUTLET_CODE_TAKEN` |
| PATCH | `/outlets/:id` | `admin.settings` EDIT | partial, plus `isActive` |

## Devices
| Method | Path | Permission | Body → Response / Notes |
|--------|------|------------|-------------------------|
| GET | `/devices` | `admin.settings` VIEW | `?outletId=` |
| POST | `/devices` | `admin.settings` EDIT | `{ outletId, name, type }` → `{ device, deviceKey }`. The key is shown once (only its sha256 is stored) |
| DELETE | `/devices/:id` | `admin.settings` EDIT | sets `isActive = false` |

Device types: `POS_TABLET`, `KDS`, `TV`, `KIOSK`, `PRINTER`, `PHONE`.

## Notifications
| Method | Path | Notes |
|--------|------|-------|
| GET | `/notifications?unreadOnly=true` | → `{ data: [...], unreadCount }`. Rows for the caller in the current outlet or tenant-wide: addressed to the caller, or sent to a permission the caller holds at VIEW or above |
| POST | `/notifications/:id/read` | |
| POST | `/notifications/read-all` | → `{ success, count }` |

## Users (ADMIN)
Requires `admin.users`. Users are tenant-scoped; deleted users return 404.

| Method | Path | Permission | Body / Notes |
|--------|------|------------|--------------|
| GET | `/users` | `admin.users` VIEW | list (paginated, search). Each user has `displayName`, `phone`, `outlets: [{ outletId, outletName, personaId, personaName, isDefault }]`, `hasPin` |
| POST | `/users` | `admin.users` EDIT | `{ username, email, password, roleName?, displayName?, phone? }`. `roleName` (`ADMIN`, `USER`, `KIOSK`) picks the starting persona (admin, cashier, kiosk) at the first active outlet |
| GET | `/users/:id` | `admin.users` VIEW | |
| PATCH | `/users/:id` | `admin.users` EDIT | `{ email?, displayName?, phone?, isActive?, roleName?, password? }` |
| PATCH | `/users/:id/reset-password` | `admin.users` EDIT | `{ newPassword }`. Bumps `tokenVersion` |
| PATCH | `/users/:id/pin` | `admin.users` EDIT | `{ pin }` (4 digits). 400 `PIN_TOO_SIMPLE` for `0000`, `1111`…`9999`, `1234`, `4321`. Clears any lock |
| PUT | `/users/:id/outlets` | `admin.users` EDIT | `{ items: [ { outletId, personaId, isDefault? } ] }` replaces all assignments; one default (the first item when none is marked). 400 `DUPLICATE_OUTLET`, `DEFAULT_OUTLET_INVALID`, `INVALID_REFERENCE` |
| DELETE | `/users/:id` | `admin.users` EDIT | soft delete (`deletedAt` set, `isActive = false`) |
| GET | `/users/:id/features` | `admin.users` VIEW | deprecated legacy feature grants |
| PUT | `/users/:id/features` | `admin.users` EDIT | deprecated legacy feature grants |

## Products
| Method | Path | Role | Notes |
|--------|------|------|-------|
| GET | `/products` | auth | search, `?isActive=`, paginated |
| GET | `/products/:id` | auth | |
| POST | `/products` | ADMIN | `{ name, description?, price, taxPercentage? }` |
| PATCH | `/products/:id` | ADMIN | partial update |
| PATCH | `/products/:id/status` | ADMIN | `{ isActive }` |
| DELETE | `/products/:id` | ADMIN | soft delete |
| POST | `/products/:id/image` | ADMIN | multipart `file` |
| POST | `/products/import` | ADMIN | multipart `.xlsx` → import summary |
| GET | `/products/import/template` | ADMIN | downloadable template |

## Tax
| Method | Path | Role | Notes |
|--------|------|------|-------|
| GET | `/tax/global` | auth | active global tax |
| PUT | `/tax/global` | ADMIN | `{ percentage }` |
| PATCH | `/tax/products/:id` | ADMIN | `{ taxPercentage|null }` override |

## Orders
| Method | Path | Role | Notes |
|--------|------|------|-------|
| POST | `/orders` | auth | `{ items:[{productId, quantity}] }` — totals computed server-side |
| GET | `/orders` | auth | search by invoiceNumber, date range, paginated |
| GET | `/orders/:id` | auth | full detail incl. items + payments |

## Payments
| Method | Path | Role | Notes |
|--------|------|------|-------|
| POST | `/payments` | auth | `{ orderId, amount, paymentMethod }` → updates order status |
| GET | `/payments/order/:orderId` | auth | payments for an order |
| POST | `/payments/:id/refund` | ADMIN | mark refunded |

## Invoice
| Method | Path | Role | Notes |
|--------|------|------|-------|
| GET | `/invoice/:orderId/thermal` | auth | 80mm printer-friendly HTML |
| GET | `/invoice/:orderId/pdf` | auth | A4 PDF download |

## Reports (ADMIN)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/reports/dashboard` | today orders/revenue/tax, monthly revenue/tax |
| GET | `/reports/top-products?limit=10` | top selling products |
| GET | `/reports/recent-orders?limit=10` | recent orders |

## Menu, settings, floor and hardware (Phase 2)
Outlet-scoped routes use the caller's outlet. Menu catalogue routes are tenant-wide. Money is returned as strings with two decimals.

**Menu**
| Method | Path | Permission | Notes |
|--------|------|------------|-------|
| GET | `/menu/pos` | `sales.orders.take` VIEW | `{ categories, products, modifierGroups, combos, priceRules, taxClasses, settings }` in one call. Inactive rows are left out. 86'd products stay with `is86: true`. `priceRules[].activeNow` and `endsAt` use outlet time |
| GET / POST | `/categories` | `menu.edit` VIEW / EDIT | category has `station` (routing key), `ticketKind` (KOT or BOT), `taxClassId`, `color` |
| PATCH | `/categories/:id` | `menu.edit` EDIT | partial |
| DELETE | `/categories/:id` | `menu.edit` EDIT | soft delete. 409 `CATEGORY_IN_USE` (`details.count`) while active products use it |
| PATCH | `/products/:id` | `menu.edit` EDIT | also accepts `categoryId`, `taxClassId`, `sortOrder`. 400 `CATEGORY_NOT_FOUND`, `TAX_CLASS_NOT_FOUND` |
| PUT | `/products/:id/variants` | `menu.edit` EDIT | `{ items: [{ id?, name, price, isDefault?, sortOrder? }] }` replaces the list. Omitted variants are deactivated. Exactly one default: two defaults give 400 `VARIANT_DEFAULT_MULTIPLE`, none makes the first one the default. 400 `VARIANT_NAME_DUPLICATE`, `VARIANT_NOT_FOUND` |
| PUT | `/products/:id/modifier-groups` | `menu.edit` EDIT | `{ groupIds }` replaces the attached groups. 400 `MODIFIER_GROUP_NOT_FOUND` |
| POST | `/products/:id/86` | `menu.mark86` EDIT | `{ is86 }`. Notifies the outlet when the state changes |
| GET / POST | `/modifier-groups` | `menu.edit` VIEW / EDIT | `{ name, minSelect, maxSelect, showOn: ['POS','QR','KIOSK'], options: [{ name, priceDelta, sortOrder? }] }` |
| PUT | `/modifier-groups/:id` | `menu.edit` EDIT | full replacement. Options listed with `id` are updated, options without one are created, others are deactivated. 400 `MODIFIER_RULES`, `MODIFIER_OPTION_NOT_FOUND` |
| DELETE | `/modifier-groups/:id` | `menu.edit` EDIT | soft delete |
| GET / POST | `/combos` | `menu.edit` VIEW / EDIT | `{ name, price, taxClassId?, days?, startTime?, endTime?, items: [{ productId, variantId?, quantity?, swapAllowed? }] }` |
| PUT | `/combos/:id` | `menu.edit` EDIT | full replacement including `items`. 400 `PRODUCT_NOT_FOUND`, `VARIANT_NOT_FOUND` |
| DELETE | `/combos/:id` | `menu.edit` EDIT | soft delete |
| GET / POST | `/price-rules` | `menu.edit` VIEW / EDIT | happy hour: `{ name, outletId?, percentOff, categoryIds, productIds, days, startTime, endTime }`. `outletId` must be null or the current outlet (400 `OUTLET_MISMATCH`). Windows may cross midnight |
| PATCH / DELETE | `/price-rules/:id` | `menu.edit` EDIT | DELETE is soft |
| GET / POST | `/tax-classes` | `admin.settings` VIEW / EDIT | `{ name, code, rate, components: [{ name, rate }], inclusive?, isLiquor? }`. Components must add up to `rate` (400 `TAX_COMPONENTS_MISMATCH`). 409 `TAX_CODE_TAKEN` |
| PATCH / DELETE | `/tax-classes/:id` | `admin.settings` EDIT | DELETE is soft. 409 `TAX_CLASS_IN_USE` (`details.products`, `details.categories`) |
| GET / PUT | `/outlet-settings` | `admin.settings` VIEW / EDIT | `{ serviceChargePercent, serviceChargeTypes, roundingMode, orderPrefix, invoicePrefix, countryCode? }` |

**Floor**
| Method | Path | Permission | Notes |
|--------|------|------------|-------|
| GET / POST | `/areas` | `sales.orders.take` VIEW / `admin.settings` EDIT | `{ name, priceMarkupPercent?, isSmoking?, sortOrder? }` |
| PATCH / DELETE | `/areas/:id` | `admin.settings` EDIT | DELETE is soft. 409 `AREA_IN_USE` while it has active tables |
| GET | `/tables` | `sales.orders.take` VIEW | live floor view: `[{ id, name, areaId, seats, shape, posX, posY, status, mergedIntoId, order: { id, orderNumber, covers, grandTotal, openedAt, waiterName } \| null }]` |
| POST | `/tables` | `admin.settings` EDIT | `{ areaId, name, seats?, shape?, posX?, posY? }`. 409 `TABLE_NAME_TAKEN` |
| PATCH / DELETE | `/tables/:id` | `admin.settings` EDIT | DELETE is soft. 409 `TABLE_HAS_OPEN_ORDER` |
| PATCH | `/tables/:id/status` | `sales.orders.take` EDIT | `{ status: FREE \| CLEANING \| RESERVED }`. 409 `TABLE_HAS_OPEN_ORDER` unless the status is CLEANING |

**Hardware**
| Method | Path | Permission | Notes |
|--------|------|------------|-------|
| GET / POST | `/printers` | `admin.settings` VIEW / EDIT | `{ name, connection: LAN, USB, BLUETOOTH, host?, port?, paperWidth: 58 or 80, copies?, language?, isReceipt?, isActive? }`. A LAN printer needs a valid IPv4 address or hostname (400 `PRINTER_HOST_REQUIRED`, `PRINTER_HOST_INVALID`) |
| PATCH / DELETE | `/printers/:id` | `admin.settings` EDIT | DELETE deactivates the printer |
| POST | `/printers/:id/test` | `admin.settings` EDIT | queues a TEST print job (404 `PRINTER_NOT_FOUND`) |
| GET / PUT | `/station-routes` | `admin.settings` VIEW / EDIT | `{ items: [{ station, printerId, fallbackPrinterId }] }` replaces the outlet's routes. 400 `DUPLICATE_STATION`, `PRINTER_NOT_IN_OUTLET` |
| GET | `/print-jobs/next` | `X-Device-Key` (PRINTER or POS_TABLET device) | claims up to 10 QUEUED jobs for the device's outlet and marks them SENT. Returns `[{ id, kind, printer: { host, port, paperWidth, copies }, payload }]` |
| POST | `/print-jobs/:id/result` | `X-Device-Key` | `{ ok, error?, printerStatus?: READY, PAPER_LOW, OFFLINE }`. Success completes the job (and marks the ticket PRINTED). Failure requeues it, up to 3 attempts. A ticket job moves to the station's fallback printer first. At the limit the job and ticket are FAILED and a notification is sent to the outlet. 409 `PRINT_JOB_NOT_IN_PROGRESS` |

Payloads are structured lines (`{ lines: [{ text, bold?, align?, size? }], cut, openDrawer? }`). The print agent in `print-agent/` converts them to ESC/POS. Only PRINTER and POS_TABLET devices may poll for or report print jobs.

## Orders (Phase 2)

All under `/api/v1`, outlet = the caller's outlet. Money is a string with 2 decimals. `OrderView` is the shape in `docs/phase-2/PLAN.md` 1.4 (`items`, `discounts`, `payments`, `totals`, `invoiceNumber`).

| Method | Path | Permission | Notes |
|---|---|---|---|
| POST | `/orders` | `sales.orders.take EDIT` | `{ type, tableId?, covers?, waiterId?, note?, offlineId?, items? }`. Idempotent on `offlineId`. Dine-in claims the table (409 `TABLE_OCCUPIED`). Legacy body `{ items: [{productId, quantity}] }` (no `type`) is a takeaway order and also returns `subtotal`, `taxAmount`, `grandTotal`. |
| GET | `/orders` | `sales.orders.take VIEW` | Legacy history search (unchanged). |
| GET | `/orders/open` | `sales.orders.take VIEW` | `{ data: [...] }` of OPEN, SENT, BILLED orders. |
| GET | `/orders/:id` | `sales.orders.take VIEW` | `OrderView`. |
| POST | `/orders/:id/items` | `sales.orders.take EDIT` | `{ items: [AddItem] }`. 400 `ITEM_86`, `ITEM_UNAVAILABLE`, `MODIFIER_RULES`, `COMBO_UNAVAILABLE`. |
| PATCH / DELETE | `/orders/:id/items/:itemId` | `sales.orders.take EDIT` | Only lines still `NEW`, else 409 `ITEM_ALREADY_SENT`. PATCH takes `{ quantity?, seat?, note?, modifierOptionIds? }`. |
| POST | `/orders/:id/send` | `sales.orders.take EDIT` | One ticket per station and kind. `{ order, tickets: [{id, kind, station, seq}] }`. 400 `NOTHING_TO_SEND`. |
| POST | `/orders/:id/hold`, `/unhold` | `sales.orders.take EDIT` | Sets or clears `heldAt`. |
| POST | `/orders/:id/discounts` | `sales.discount.give REQUEST` | `{ type: PERCENT\|FLAT, value, itemIds?, reason, approvalId? }`. Above the LIMITED limit: 403 `APPROVAL_REQUIRED` `{ limit }`, unless the approval matches (`APPROVAL_MISMATCH`, `APPROVAL_EXPIRED`). Liquor lines: 400 `LIQUOR_DISCOUNT_NOT_ALLOWED`. |
| DELETE | `/orders/:id/discounts/:discountId` | `sales.discount.give EDIT` | |
| POST | `/orders/:id/void-items` | `sales.void REQUEST` | `{ itemIds, reason, approvalId? }`. Sent lines print a cancellation ticket and log wastage. Without APPROVE on `sales.void`, 403 `APPROVAL_REQUIRED` unless an approval is given. |
| POST | `/orders/:id/void` | `sales.void REQUEST` | `{ reason, approvalId? }`. 409 `ORDER_HAS_PAYMENTS`. Table to FREE. |
| POST | `/orders/:id/move` | `sales.orders.take EDIT` | `{ toTableId, force? }`. 400 `TABLE_TOO_SMALL` `{ seats, covers }` unless `force`. 409 `TABLE_OCCUPIED`. |
| POST | `/orders/:id/merge` | `sales.orders.take EDIT` | `{ fromOrderId }`. The source order is voided ("merged into A-…") and its table freed. |
| POST | `/orders/:id/transfer-items` | `sales.orders.take EDIT` | `{ itemIds, toOrderId? , toTableId? }`. |
| POST | `/orders/:id/bill` | `sales.payments.take VIEW` | `{ copies? }`. Order to BILLED, dine-in table to BILL_PRINTED. 409 `UNSENT_ITEMS`. |
| GET | `/orders/:id/split` | `sales.payments.take VIEW` | `?mode=EQUAL&parts=3` \| `SEAT` \| `ITEMS&assign=itemId:seat,…`. `{ grandTotal, shares: [{ label, seat, itemIds, amount, paid, due }] }`. Shares sum to `grandTotal`. |
| POST | `/orders/:id/payments` | `sales.payments.take EDIT` | `{ payments: [{ method, amount, tendered?, reference?, seat? }], tipAmount?, completeSeat? }`. 400 `PAYMENT_EXCEEDS_DUE` `{ due }`, `TENDERED_TOO_LOW`, `SEAT_NOT_FULLY_PAID`. Returns `{ order, change }`. On full payment: invoice number (outlet `invoicePrefix`, once), dine-in to PAID and table to CLEANING; takeaway and bar counter to CLOSED. A cash line opens the drawer. |
| POST | `/orders/:id/close` | `sales.payments.take EDIT` | PAID to CLOSED, table to CLEANING. 409 `ORDER_NOT_PAID`. |
| POST | `/orders/:id/refund` | `sales.payments.take EDIT` | `{ amount, reason, paymentId?, approvalId? }`. Needs APPROVE on `sales.void` or an approved REFUND approval. Negative payment row. 400 `REFUND_EXCEEDS_PAID`. |
| POST | `/payments` | `sales.payments.take EDIT` | Legacy: `{ orderId, amount, paymentMethod }`, returns `{ payment, order }`. |
| POST | `/payments/:id/refund` | `sales.payments.take EDIT` | Legacy full refund. |

### Approvals

| Method | Path | Permission | Notes |
|---|---|---|---|
| POST | `/approvals` | `sales.orders.take EDIT` | `{ type: DISCOUNT\|VOID\|REFUND\|NO_SALE, orderId?, payload, reason }`. PENDING for 15 min, notifies approvers. |
| POST | `/approvals/pin` | `sales.orders.take EDIT` | `{ type, orderId?, payload, reason, managerUserId, pin }`. Creates and approves at once. 403 `APPROVER_NOT_ALLOWED` (needs APPROVE on the key), 401 `PIN_INVALID` `{ attemptsLeft }`, 423 `PIN_LOCKED`. |
| GET | `/approvals/:id` | auth | Poll while waiting. Pending past expiry becomes EXPIRED. |
| GET | `/approvals?status=PENDING` | auth | `{ data: [...] }`. |
| POST | `/approvals/:id/decide` | APPROVE on the key | `{ decision: APPROVED\|DECLINED }`. 409 `APPROVAL_NOT_PENDING`. |

### Reports and cash drawer

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/reports/x` | `reports.view LIMITED` | Live totals for the current business date (05:00 cut-off). Not saved. Shape in PLAN.md 1.6. |
| POST | `/reports/x/print` | `reports.view LIMITED` | Prints the X report on the receipt printer. |
| POST | `/reports/z` | `reports.view EDIT` | `{ cashCounted, force? }`. Saves a DayClose and links the day's orders. 409 `DAY_ALREADY_CLOSED`, `OPEN_ORDERS_EXIST` `{ count }`. Returns `{ id, businessDate, cashCounted, cashExpected, variance, totals }`. |
| GET | `/reports/day-closes` | `reports.view LIMITED` | `{ data: [...] }`, latest 50. |
| POST | `/cash-drawer/open` | `sales.orders.take EDIT` | `{ reason, approvalId? }`. Opens directly with `sales.payments.take EDIT`; otherwise needs an approved NO_SALE approval (403 `APPROVAL_REQUIRED`). Audited. |

## Bar tabs, KDS and realtime (Phase 3)

All under `/api/v1`, outlet = the caller's outlet. Money is a string with 2 decimals, percentages a string with 1 decimal. `TabView`, `LockerView`, `KdsTicket` and `ReadyItem` are the shapes in `docs/phase-3/PLAN.md` 1.7.

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/tabs` | `sales.tab.open VIEW` | `?status=OPEN\|CLOSED&scope=today\|all&openedById`. `{ counts: { open, nearLimit, closedToday }, items: [TabView] }`. |
| GET | `/tabs/:id` | `sales.tab.open VIEW` | `TabView` plus `order: OrderView`. 404 `TAB_NOT_FOUND`. |
| POST | `/tabs` | `sales.tab.open LIMITED` | `{ guestName, mobile?, ageChecked, security: CARD_PREAUTH\|CASH_DEPOSIT\|HOUSE_ACCOUNT\|NONE, cardLast4?, amountHeld?, houseAccount?, tabLimit, warnAtPercent?: 80\|90, linkType: BAR_SEAT\|TABLE\|QUEUE_TOKEN\|NONE, linkLabel?, tableId?, approvalId? }`. Creates a BAR_COUNTER order (DINE_IN with `TABLE`). 400 `AGE_CHECK_REQUIRED`, `CARD_LAST4_REQUIRED`, `DEPOSIT_REQUIRED`, `HOUSE_ACCOUNT_REQUIRED`, `TABLE_REQUIRED`; 403 `LIMIT_EXCEEDED`, `APPROVAL_REQUIRED` (security NONE without APPROVE; `approvalId` is a `TAB_NO_SECURITY` approval with payload `{ guestName, tabLimit }`); 409 `TABLE_OCCUPIED`. |
| PUT | `/tabs/:id` | `sales.tab.open LIMITED` | `{ guestName?, mobile?, tabLimit?, warnAtPercent?, linkType?, linkLabel? }`. A new `tabLimit` is checked with the same limit rule and re-arms the warning. 409 `TAB_CLOSED`, `TAB_ON_TABLE`. |
| POST | `/tabs/:id/move-to-table` | `sales.tab.open LIMITED` | `{ tableId }`. The order becomes DINE_IN and the old table is freed. 409 `TAB_CLOSED`, `TABLE_OCCUPIED`. |
| POST | `/tabs/:id/close` | `sales.payments.take EDIT` | Bills the order. A cash deposit pays `min(held, total)` as a CASH payment with reference `TAB_DEPOSIT`. Returns `{ tab, orderId, depositApplied, depositToReturn }`. The tab closes when the order is fully paid. 400 `TAB_EMPTY`; 409 `TAB_CLOSED`. |
| POST | `/tabs/:id/void` | `sales.tab.open LIMITED` | `{ reason }`. Only an empty tab. 409 `TAB_NOT_EMPTY`. |
| GET | `/locker` | `sales.tab.open VIEW` | `?status=&search=`. `[LockerView]`. |
| POST | `/locker` | `sales.tab.open LIMITED` | `{ guestName, mobile?, cardLast4?, stockItemId?, bottleName, bottleMl, remainingMl, expiresAt: "YYYY-MM-DD", orderItemId?, note? }`. 400 `INVALID_ML`. |
| POST | `/locker/:id/serve` | `sales.tab.open LIMITED` | `{ ml }`. Reaching zero finishes the entry. 409 `NOT_ENOUGH_LEFT` `{ remainingMl }`, `LOCKER_EXPIRED`. |
| PUT | `/locker/:id` | `sales.tab.open LIMITED` | `{ guestName?, mobile?, remainingMl?, expiresAt?, note? }`. A changed volume writes an ADJUST event. |
| DELETE | `/locker/:id` | `sales.tab.open LIMITED` | Body `{ reason }`. Marks the entry REMOVED. |
| GET | `/kds/tickets` | `kds.bump VIEW` | `?station=BAR\|KITCHEN\|ALL&view=active\|done`. `{ serverTime, tickets: [KdsTicket], allDay: [{ name, variantName, quantity }], avgTicketSeconds }`. Done = SERVED in the last two hours. |
| POST | `/kds/tickets/:id/start` | `kds.bump EDIT` | NEW to PREPARING. 409 `KDS_BAD_STATE` `{ status }`. |
| POST | `/kds/tickets/:id/bump` | `kds.bump EDIT` | NEW or PREPARING to READY. Notifies the waiter (`type: ready`). 409 `KDS_BAD_STATE`. |
| POST | `/kds/tickets/:id/recall` | `kds.bump EDIT` | READY, or SERVED within 30 minutes, to PREPARING. 409 `KDS_BAD_STATE`, `RECALL_TOO_LATE`. |
| POST | `/kds/tickets/:id/served` | `sales.orders.take EDIT` or `kds.bump EDIT` | READY to SERVED; the ticket's lines become SERVED. 409 `KDS_BAD_STATE`. |
| GET | `/kds/ready` | `sales.orders.take VIEW` or `kds.bump VIEW` | `?mine=true`. `[ReadyItem]`, oldest first. |
| GET | `/kds/stations` | `kds.bump VIEW` | `[{ station, label, activeCount }]`. |

Errors added to the Phase 2 orders routes: `POST /orders/:id/items` and `PATCH /orders/:id/items/:itemId` return 409 `TAB_LIMIT_REACHED` `{ tabId, number, limit, spent, attempted }` when the order is on an open tab and the new total is above the limit. The change is rolled back. `OrderView` has a `tab` field (`{ id, number, tabLimit, spent, nearLimit }` or null).

### Realtime

Socket.io on namespace `/rt` (`cors` as the REST API). Connect with `auth: { token, stations? }`, where `token` is the access token and `stations` an optional list such as `["BAR"]`. A missing or invalid token, an outlet-selection token, or revoked outlet access disconnects at once. Rooms: `outlet:<outletId>`, `user:<userId>`, `outlet:<outletId>:station:<station>` for each requested station. A station list containing `*` joins `outlet:<outletId>:station:*`, which receives every station's KDS events.

| Event | Room | Payload |
|---|---|---|
| `kds.ticket.created` | station | `KdsTicket` (not for cancellation tickets) |
| `kds.ticket.updated` | station | `KdsTicket` (after start, bump, recall, served, or a void of its lines) |
| `kds.ready` | `user:<waiterId>` and outlet | `ReadyItem` |
| `menu.item86` | outlet | `{ productId, name, is86, auto }` |
| `stock.low` | outlet | `{ stockItemId, name, locationId, locationName, onHand, parLevel }` |
| `tab.nearLimit` | outlet | `TabView` |
| `order.updated` | outlet | `{ orderId, status }` after send, bill, void, payment |

## Inventory (Phase 3)

Quantities are base units (ML, G, PC) as strings with 3 dp; money is a string with 2 dp; unit costs have 6 dp. Every quantity has a `…Display` string (`"8 btl + 410 ml"`). Permissions are in PLAN.md 1.6.

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/inventory/summary` | `stock.count VIEW` or `reports.view LIMITED` | `{ stockValue, pourCost7d: { percent, cost, revenue }, liquorVariance7d: { qty, value }, belowParCount }` |
| GET | `/stock/locations` | `stock.count VIEW` | `[{ id, name, kind, stations, isDefaultSales, itemCount, value }]` |
| POST / PUT | `/stock/locations`, `/stock/locations/:id` | `menu.edit EDIT` or `stock.purchaseOrders EDIT` | `409 LOCATION_EXISTS` |
| GET | `/stock/items` | `stock.count VIEW` | `?locationId&search&status=BELOW_PAR\|VARIANCE\|EXPIRES\|NEGATIVE\|OK&liquor=true` |
| GET | `/stock/items/:id` | `stock.count VIEW` | Row plus input fields, `levels` per location, `preferredVendor`. `404 STOCK_ITEM_NOT_FOUND` |
| POST / PUT | `/stock/items`, `/stock/items/:id` | `menu.edit EDIT` or `stock.purchaseOrders EDIT` | Create takes `opening: [{ locationId, qty }]` (OPENING movements). `409 STOCK_ITEM_EXISTS` |
| PUT | `/stock/items/:id/par` | `menu.edit EDIT` or `stock.purchaseOrders EDIT` | `{ levels: [{ locationId, parLevel }] }` |
| GET | `/stock/items/:id/movements` | `stock.count VIEW` | `?locationId&from&to&limit=100` |
| GET / POST | `/stock/transfers` | `stock.count VIEW` / `EDIT` | POST `{ fromLocationId, toLocationId, note?, lines: [{ stockItemId, qty }] }`. `400 SAME_LOCATION`, `400 EMPTY_TRANSFER` |
| GET / POST | `/stock/counts` | `stock.count VIEW` / `EDIT` | POST `{ locationId }`. `409 COUNT_ALREADY_OPEN` (`{ countId }`) |
| GET | `/stock/counts/:id` | `stock.count VIEW` | Lines with `expectedQty` (live until submit), `differencePercent`, `outlier`. `404 COUNT_NOT_FOUND` |
| PUT | `/stock/counts/:id/lines` | `stock.count EDIT` | `{ lines: [{ stockItemId, countedQty, note?, confirmedOutlier?, countedAt? }] }`, idempotent. `409 COUNT_NOT_OPEN` |
| POST | `/stock/counts/:id/submit` | `stock.count EDIT` | Snapshots `expectedQty`. `400 NOTHING_COUNTED`, `409 COUNT_NOT_OPEN` |
| POST | `/stock/counts/:id/post` | `stock.count APPROVE` | COUNT_ADJUST movements. `409 COUNT_NOT_SUBMITTED` |
| POST | `/stock/counts/:id/cancel` | `stock.count EDIT` | `409 COUNT_POSTED` |
| GET / POST | `/stock/wastage` | `stock.count VIEW` / `EDIT` | GET `?from&to&locationId` returns `{ items, totalValue }`. POST `{ locationId, stockItemId, qty, reason, note?, photoUrl? }`. `400 PHOTO_REQUIRED` (above ₹2,000), `409 INSUFFICIENT_STOCK` (`{ onHand, onHandDisplay }`), `400 INVALID_REASON` |
| POST | `/stock/uploads` | `stock.count EDIT` | Multipart `file`, jpg/png/pdf up to 8 MB, checked by content. Returns `{ url }`. `400 INVALID_FILE` |
| GET | `/stock/variance` | `stock.count VIEW` or `reports.view LIMITED` | `?locationId&from&to&liquor=true` (default: last 7 business days, liquor only). Returns `{ from, to, rows, totals: { varianceValue } }` |
| GET | `/stock/kegs` | `stock.count VIEW` | Keg items: `fullKegs`, `onTapMl` (bar stock modulo one keg), `locationBreakdown` |
| GET | `/products/:id/recipes` | `stock.count VIEW` and `menu.edit VIEW` | One view per variant with a recipe, plus `variantId: null`. Costing and pour cost |
| PUT | `/products/:id/recipes` | `menu.edit EDIT` | `{ recipes: [{ variantId, note?, lines: [{ stockItemId, qty, wastagePercent }] }] }`, replaces all. `400 RECIPE_DUPLICATE_VARIANT` |
| PUT | `/modifier-groups/:id` (Phase 2) | `menu.edit EDIT` | Options may carry `stockItemId` and `stockQty`; responses add `stockItemId`, `stockQty` (3 dp), `stockItemName` |

## Procurement (Phase 3)

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/vendors` | `stock.purchaseOrders VIEW` | `?active=true`. `openPoCount` |
| POST / PUT | `/vendors`, `/vendors/:id` | `stock.purchaseOrders EDIT` | `409 VENDOR_EXISTS` |
| GET | `/purchase-orders` | `stock.purchaseOrders VIEW` | `?status&vendorId`. Returns `{ counts, items }` |
| GET | `/purchase-orders/:id` | `stock.purchaseOrders VIEW` | Lines and linked GRNs. `404 PO_NOT_FOUND` |
| POST | `/purchase-orders` | `stock.purchaseOrders REQUEST` | `{ vendorId, locationId, dueDate?, transportPermitNo?, note?, lines: [{ stockItemId, qty, rate }] }`. `400 EMPTY_PO` |
| PUT / DELETE | `/purchase-orders/:id` | `stock.purchaseOrders REQUEST` | PUT only for DRAFT or PENDING_APPROVAL (returns to DRAFT). DELETE only for DRAFT. `409 PO_NOT_EDITABLE` |
| POST | `/purchase-orders/:id/submit` | `stock.purchaseOrders REQUEST` | To PENDING_APPROVAL and notifies approvers |
| POST | `/purchase-orders/:id/approve` | `stock.purchaseOrders APPROVE` | `409 PO_NOT_PENDING` |
| POST | `/purchase-orders/:id/send` | `stock.purchaseOrders APPROVE` | From APPROVED, or from DRAFT or PENDING_APPROVAL (auto-approved). `409 PO_NOT_APPROVED` |
| POST | `/purchase-orders/:id/cancel` | `stock.purchaseOrders APPROVE` | `{ reason }`. `409 PO_RECEIVED` |
| GET | `/purchase-orders/reorder-suggestions` | `stock.purchaseOrders VIEW` | `?locationId`. Items below par with `suggestedQty` in purchase units |
| POST | `/purchase-orders/reorder-request` | `stock.purchaseOrders REQUEST` | `{ locationId, lines: [{ stockItemId, qty }] }`. One PENDING_APPROVAL PO per vendor. `400 VENDOR_MISSING` (`{ stockItemIds }`) |
| GET | `/grns` | `stock.purchaseOrders VIEW` | `?from&to&vendorId` |
| GET | `/grns/:id` | `stock.purchaseOrders VIEW` | Lines with status, and `preview` (stock added, debit note, wastage, payable). `404 GRN_NOT_FOUND` |
| POST | `/grns` | `stock.purchaseOrders REQUEST` | With `poId` and no lines, lines are the PO's outstanding quantities. `409 PO_NOT_RECEIVABLE` |
| PUT | `/grns/:id` | `stock.purchaseOrders REQUEST` | Draft only. `409 GRN_POSTED` |
| POST | `/grns/:id/post` | `stock.purchaseOrders REQUEST` | Receipts, damaged wastage, debit note, PO status. `400 INVOICE_NO_REQUIRED`, `400 PERMIT_REQUIRED`, `400 INVALID_QTY` (`{ line, field }`) |
| GET | `/debit-notes` | `stock.purchaseOrders VIEW` | `?status` |
| POST | `/debit-notes/:id/settle` | `stock.purchaseOrders EDIT` | `409 DEBIT_NOTE_NOT_OPEN` |

## Error envelope
```json
{ "statusCode": 400, "message": "…", "error": "Bad Request", "code": "PIN_TOO_SIMPLE", "details": {}, "path": "/api/v1/…", "timestamp": "…" }
```

`code` is always present: a stable machine-readable value, or a default derived from the status (for example `FORBIDDEN`). `details` is present only when the error carries extra data. Codes used in Phase 1: `INVALID_CREDENTIALS`, `NO_OUTLET_ACCESS`, `SELECTION_EXPIRED`, `RESET_TOKEN_INVALID`, `DEVICE_INVALID`, `PIN_INVALID`, `PIN_LOCKED`, `PIN_TOO_SIMPLE`, `PERMISSION_DENIED`, `LIMIT_EXCEEDED` (Phase 2), `LIMIT_NOT_SUPPORTED`, `UNKNOWN_PERMISSION`, `PERSONA_SYSTEM`, `PERSONA_IN_USE`, `OUTLET_CODE_TAKEN`, `DUPLICATE_OUTLET`, `DEFAULT_OUTLET_INVALID`, `INVALID_REFERENCE`.
