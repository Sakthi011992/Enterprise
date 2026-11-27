# Phase 4 — Guest QR table ordering: implementation plan

Branch: `phase-1-foundation` (new PR after PR #2). Builds on Phases 1–3 (`docs/phase-{1,2,3}/PLAN.md`, `docs/phase-3/INTEGRATION.md`).

**Status: READY TO BUILD.** All questions in section 6 are answered except **Q-9** (public HTTPS hosting) and **Q-13** (where guests see the static OTP), which are on hold. Neither blocks the build: development and the exit test run on the local network and emulator, and the code works with either OTP placement. Online payment is a **placeholder** in this phase (Q-2).

**UI design (approved): `docs/phase-4/ui/guest-ordering-ui.html`.** Open it in a browser or read its markup. It's the source of truth for every guest screen (phone, tablet, desktop) and the staff screens: copy, layout, states and colours (Pegs & Bottles tokens). Older boards in `docs/ui-design/project/` (GuestMobile, Flow-guest, MobileStaff, KDS, FloorPlan) are background only.

---

## What we are building

A diner scans the QR code on their table and enters their **name and mobile number**. They then verify it with a code (2.3):

- **Static OTP:** one code set by the admin, standing in for SMS OTP for now.
- **Table PIN:** a 4-digit PIN that staff give to the seated table.

Once verified, they see the outlet's menu, add food and drinks, and place the order to their table. Everyone at the table who scans the same code joins the same table session and orders into the same bill.

The administrator chooses **one app-wide routing** in feature configuration. Every placed round then goes one of two ways:

- **Direct to kitchen.** The round goes straight to the KOT/BOT and appears on the kitchen and bar displays.
- **Via waiter.** The round waits for a waiter. The waiter checks it, can edit or remove lines, and confirms it. It then goes to KOT/BOT.

The guest sees each item's state live: *Waiting for waiter* → *Sent to kitchen* → *Cooking* → *Ready to serve* → *Served*. They also see the running total.

**Checkout** alerts the waiter ("R4 asks for the bill"), who brings the bill and takes payment on the existing pay screen. This works the same for both routing modes. A **"Pay online"** button is shown as a placeholder ("Coming soon", disabled) until a payment gateway is integrated in a later phase (Q-2).

After payment the table session ends and the table's QR link is rotated.

**Exit test (pilot gate):**
1. Pegs & Bottles, admin sets routing to **Via waiter** and verification to **Static OTP**. Deepa and Arun scan table **R4**'s QR on two phones, enter their name and mobile number, type the code, and both join "Table R4". A wrong code shows "That code doesn't match" and five wrong tries lock the attempt for 10 min. Deepa adds 2 × Classic Mojito (happy-hour price shown) and Arun adds Chicken Wings. Each places their round. Waiter Ravi gets **"New guest order · R4"** on his phone within 2 s. He removes nothing and taps **Confirm & send**. A BOT appears on the Bar KDS and a KOT on the Kitchen KDS. Both guests see "Sent to kitchen".
2. The chef taps Start, then Bump. The guests see Wings move to **Cooking** and then **Ready to serve**. Ravi gets the existing "Ready to serve" alert and marks it Served. The guests see **Served**.
3. Deepa taps **Checkout**. Ravi gets **"R4 asks for the bill"**. He bills the order (existing `/orders/:id/bill`) and takes ₹X by UPI on the pay screen. The order closes and the table goes to Cleaning. Both phones show "Thank you · paid". Reopening the old QR link shows "This table's session has ended" until staff seat the next guests.
4. Admin switches routing to **Direct to kitchen** and verification to **Table PIN**. Staff seat table **B2**, and the floor plan shows its PIN (e.g. 4817). A guest enters name, mobile and 4817, orders, and the KOT appears on the KDS with no waiter step. On the bill, **Pay online** shows "Coming soon" and can't be tapped. **Ask for the bill** alerts the waiter as in step 3. Paying closes the order the same way, and B2 gets a new PIN for the next guests.
5. A phone that is not at the table opens R4's link while R4 is **not seated**. It sees the menu read-only ("Ask staff to seat you to start ordering") and cannot place an order (Q-4).

---

## 0. Ground rules (same as Phases 1–3)

1. Edit only the files your workstream owns (section 3). Put anything you need from another workstream in your report under "Requests".
2. Contracts in section 2 are exact: names, paths, JSON keys, HTTP methods, error codes. Do not rename.
3. Backend: **controller → service → repository**. Only repositories touch Prisma. Use `@Can(key, min)`, `@CurrentUser()`, `apiError(status, code, message)`, `PermissionsService`. Money is `Prisma.Decimal` with `round2`. Mutations run in `repo.transaction`.
4. **Reuse, don't fork.** Guest ordering must call the existing `OrdersService` (add items, send), `OrderPricing` (prices, happy hour, area markup, tax), `KdsService` events, `PaymentsService` (record payment, close) and `RealtimeService`. Do not copy pricing or ticket logic into the guest module.
5. Frontend: kit from `core/ui/ui.dart`, colours from `context.tokens` / `context.ext`, Riverpod providers like `features/pos/data/pos_repository.dart`. The guest app is phone-first, and `DensityScope(pos)` sets 52 px touch targets.
6. **Git:** each agent works only in its own worktree folder on its own branch `phase4/g-<letter>` (created by the planner from `phase-1-foundation`). Commit to that branch as you go; never push, never touch other branches or worktrees. The planner merges branches in the order of section 4. At the end write `docs/phase-4/reports/G-<letter>.md`: files changed, decisions, deviations, requests, what's untested.
7. **Database:** never run migrations or seeds against the shared `pos_billing` database. Each backend agent has its own database on the same Postgres (`pos_billing_g_<letter>`) and sets `DATABASE_URL` to it in the shell for `prisma migrate`, seed and tests.
8. **Running things:** don't start dev servers, the emulator, or anything on ports 3000, 8765, 8770 or 8780, and don't stop processes you didn't start; other sessions use them. Unit and widget tests, `flutter analyze`, `npm run build` and `npx jest` are fine. Install backend packages with `PUPPETEER_SKIP_DOWNLOAD=true npm ci` (the Chrome download fails on this machine).

---

## 1. Reuse map

| Need | Reuse (exists today) | New |
|---|---|---|
| Menu with prices, happy hour, area markup, 86'd items | `GET /menu/pos` logic in `modules/menu`, `order-pricing.ts`, `PriceRule`, availability (`menu.mark86`) | Guest projection of the same data filtered to channel `QR` |
| Modifiers shown to guests | `ModifierGroup.showOn` already has `'QR'` (`MODIFIER_CHANNELS`) | — |
| Order on a table | `Order` (DINE_IN, `tableId`, `waiterId`, `covers`), `OrdersService.create / addItems` | `Order.source`, guest actor (2.2) |
| Send to kitchen / bar | `POST /orders/:id/send` → `Ticket` KOT/BOT per station, printing | Called by the guest module (direct) or the waiter confirm (via waiter) |
| Kitchen progress | `Ticket.kdsStatus` NEW/PREPARING/READY/SERVED, `startedAt/readyAt/servedAt`, `kds.ready` events, overdue job | Item-level status for guests, derived (2.5) |
| Waiter alerts | `Notification`, `userEvent/outletEvent`, Ready-to-serve screen | Guest order requests and "bill please" (2.4) |
| Realtime | Socket.IO gateway with outlet / user / station rooms, 5 s polling fallback | Table room plus guest socket auth (2.6) |
| Bill and payment | `POST /orders/:id/bill`, `/split`, `/payments`, `/close`, pay screen, split math | Online payment for guests (Q-2) |
| Table state | `DiningTable.status` FREE/OCCUPIED/BILL_PRINTED/CLEANING, floor plan | QR token, "seated" gate, floor badges |
| Product tiles, cart, modifier picker (frontend) | `pos_product_grid.dart`, `modifier_rules.dart`, `pos_ticket_panel.dart`, `kiosk_display_screen.dart` cart pattern | Guest screens reuse these widgets |
| Waiter list UI (frontend) | `ready_to_serve_screen.dart`, mobile footer nav, notifications panel | "Guest orders" screen |
| Theme | Pegs & Bottles theme (default) | The guest app uses the outlet's assigned theme |

**Decision (architecture):** a **guest is not a staff persona.** Staff personas are permission bundles for logged-in users with PINs. Diners are anonymous, short-lived and scoped to one table. They get a **guest session** with a signed guest token instead (2.3). The staff side gets one new permission, `guests.orders.confirm` (2.7).

---

## 2. Shared contracts

### 2.1 Data model (owned by G-A) — add to `schema.prisma`

```prisma
enum OrderSource { POS KIOSK GUEST_QR }
model GuestConfig {      // app-level, one row per tenant (2.1)
  tenantId    String   @id
  config      Json     // routing "DIRECT" | "WAITER", verification, limits — shape in 2.1; staticOtp stored as a bcrypt hash
  updatedById String?
  updatedAt   DateTime @updatedAt
}
enum GuestSessionStatus { OPEN CLOSED }
enum GuestRequestStatus { PENDING CONFIRMED REJECTED CANCELLED EXPIRED }
enum ServiceRequestType { CALL_WAITER BILL }
enum ServiceRequestStatus { OPEN ACKNOWLEDGED DONE }

model Order {            // add
  source          OrderSource @default(POS)
  guestSessionId  String?
}
model OrderItem {        // add
  guestRequestId  String?   // which guest round created the line (null = staff)
  guestName       String?   // "Deepa" — shown on KOT and bill lines
}
model DiningTable {      // add
  qrToken         String   @unique   // 22-char url-safe random; rotated on session close
  guestPin        String?            // 4 digits, set when the table is seated (TABLE_PIN mode); cleared on session close
  qrEnabled       Boolean  @default(true)
}

model GuestSession {
  id            String   @id @default(uuid())
  tenantId      String
  outletId      String
  tableId       String
  orderId       String?             // the table's open order; created on the first placed round
  status        GuestSessionStatus @default(OPEN)
  ageConfirmedAt DateTime?
  openedById    String?             // staff user who seated the table (Q-4)
  createdAt     DateTime @default(now())
  closedAt      DateTime?
  participants  GuestParticipant[]
  requests      GuestOrderRequest[]
  @@index([tableId, status])
}

model GuestParticipant {
  id         String   @id @default(uuid())
  sessionId  String
  session    GuestSession @relation(fields: [sessionId], references: [id], onDelete: Cascade)
  name       String            // required, "Deepa"
  phone      String            // required, E.164 "+919876543210"
  verifiedAt DateTime?         // set by POST /guest/t/:qrToken/verify
  verifyMethod GuestVerifyMethod?
  consentAt  DateTime          // ticked "Use my number for this order and updates"
  deviceKey  String            // random id kept in the browser, so a refresh rejoins as the same person
  joinedAt   DateTime @default(now())
  lastSeenAt DateTime @default(now())
  @@unique([sessionId, deviceKey])
  @@index([phone])
}

enum GuestVerifyMethod { STATIC_OTP TABLE_PIN SMS_OTP }

model GuestVerification {        // one code challenge
  id            String   @id @default(uuid())
  tableId       String
  phone         String
  deviceKey     String
  method        GuestVerifyMethod
  codeHash      String?  // SMS_OTP only (future); STATIC_OTP and TABLE_PIN compare against settings / table
  attempts      Int      @default(0)
  lockedUntil   DateTime?
  expiresAt     DateTime // createdAt + 10 min
  verifiedAt    DateTime?
  createdAt     DateTime @default(now())
  @@index([tableId, phone])
}

model GuestOrderRequest {        // one placed "round"
  id            String   @id @default(uuid())
  tenantId      String
  outletId      String
  sessionId     String
  session       GuestSession @relation(fields: [sessionId], references: [id], onDelete: Cascade)
  participantId String
  orderId       String
  status        GuestRequestStatus @default(PENDING)
  items         Json     // [{ productId, variantId?, quantity, modifiers: [{groupId, optionId}], note? }] as submitted
  claimedById   String?  // waiter who opened it first
  decidedById   String?
  decidedAt     DateTime?
  rejectReason  String?
  createdAt     DateTime @default(now())
  expiresAt     DateTime // createdAt + guest.requestTtlMinutes; job marks EXPIRED and tells the guest
  @@index([outletId, status])
}

model ServiceRequest {
  id          String   @id @default(uuid())
  tenantId    String
  outletId    String
  sessionId   String
  tableId     String
  type        ServiceRequestType
  status      ServiceRequestStatus @default(OPEN)
  acknowledgedById String?
  createdAt   DateTime @default(now())
  doneAt      DateTime?
  @@index([outletId, status])
}
```

**App-level guest configuration (G-A)** — one row per tenant, model `GuestConfig` (`tenantId @unique`, `config Json`, `updatedById`, `updatedAt`). The administrator edits it in **Settings › Feature configuration › Guest ordering** (`admin.settings` EDIT). It applies to every outlet and table. There are no per-area or per-table overrides.

```json
{ "enabled": true,
  "routing": "WAITER",
  "verification": { "method": "STATIC_OTP", "staticOtp": "246810", "codeLength": 6 },
  "ageGate": true, "minAge": 25, "requireSeated": true, "requestTtlMinutes": 10,
  "maxQtyPerLine": 10, "maxLinesPerRound": 20, "allowGuestCancel": true, "checkout": "WAITER" }
```

- `routing`: `"DIRECT"` (every round goes straight to KOT/BOT) or `"WAITER"` (every round waits for a waiter). It's read at the moment a round is placed, so switching it affects new rounds only.
- `verification.method`: `"STATIC_OTP"` (guest types `staticOtp`), `"TABLE_PIN"` (guest types the table's `guestPin`, which staff see on the floor plan), or `"SMS_OTP"` (placeholder: shown greyed out "Coming soon" in settings and rejected by the API with `501 NOT_AVAILABLE` until an SMS provider is added).
- `staticOtp` is stored hashed (bcrypt). The settings screen shows it masked and lets the admin set a new one. The API never returns it.
- `checkout`: always `"WAITER"` in this phase. The key exists so `"ONLINE"` / `"BOTH"` can be switched on when a gateway is integrated (Q-2). The settings screen shows Online payment as disabled "Coming soon".
- Seed: `enabled true`, `routing WAITER`, `verification STATIC_OTP` with code `246810`, printed in the seed log like the demo logins.

### 2.2 Guest actor

`orders.cashierId` is required. G-A seeds one **system user per tenant**: username `qr-guest`, persona none, `isActive=false` so it can never log in, display name "QR guest". Orders and lines created by guests use it as `cashierId`/`createdById`. `Order.source = GUEST_QR`, `guestName` holds the guest's name on each line, and `waiterId` is set when a waiter confirms or claims the round. **No change to the order or pricing invariants.**

### 2.3 Guest auth (G-A)

- `GET /guest/t/:qrToken` (public) returns the table, outlet name, logo, active theme id, guest settings (safe subset: `routing`, `verification.method`, `codeLength`, `ageGate`), `seated: boolean` and `sessionOpen: boolean`.
- `POST /guest/t/:qrToken/start` (public) takes `{ deviceKey, name, phone, consent: true }` and returns `{ verificationId, method, codeLength }`.
  - Validates: name 1–40 characters; phone is an Indian mobile number (10 digits, optional +91), stored as E.164.
  - It fails with `409 TABLE_NOT_SEATED` when `requireSeated` is on and the table status is not OCCUPIED (Q-4), and with `400 CONSENT_REQUIRED` without consent.
  - Creates a `GuestVerification` with the configured method. For `SMS_OTP` (future) this is where the SMS is sent.
- `POST /guest/t/:qrToken/verify` (public) takes `{ verificationId, code }` and returns `{ guestToken, session, participant }`.
  - `STATIC_OTP`: compares `code` with the hashed `staticOtp`. `TABLE_PIN`: compares with `table.guestPin`.
  - Wrong code: `401 CODE_INVALID {attemptsLeft}`. After 5 wrong tries: `429 CODE_LOCKED {retryAfter}` for 10 min. Expired after 10 min: `410 CODE_EXPIRED`.
  - On success it opens a session if none is open, or joins the open one, and creates or updates the participant (same `deviceKey` = same person).
- A returning device whose stored guest token is still valid for the open session skips start/verify.
- **Verification provider interface** (`modules/guest-auth/verification/`): `VerificationProvider { method; start(ctx); check(ctx, code) }`, with `StaticOtpProvider`, `TablePinProvider` and a stub `SmsOtpProvider` that throws `NOT_AVAILABLE`. Adding real SMS later means implementing one class and enabling the option in settings, with no other changes.
- **Table PIN:** when staff set a table to OCCUPIED (existing `PATCH /tables/:id/status`, or a guest session opened by staff seating), G-B generates a 4-digit `guestPin` if the method is `TABLE_PIN`. It's cleared when the session closes. Staff see it on the floor plan table card and in the table's order panel.
- `guestToken` is a JWT signed with a **separate secret** `GUEST_JWT_SECRET`. Claims: `{ kind:'guest', sessionId, participantId, tableId, outletId, tenantId }`, TTL 6 h.
- `GuestAuthGuard` accepts only `kind:'guest'` tokens. Staff JWTs are rejected on `/guest/*`, and guest tokens are rejected everywhere else.
- When a session closes, its tokens stop working: the guard checks `session.status === OPEN`, cached for 30 s.
- Rate limits: start 10/min per IP and 3/min per phone, verify 5 tries per verification, place order 6/min per participant, service request 3/min per session. Over-limit returns `429 RATE_LIMITED`.
- **Personal data:** phone numbers are personal data under India's DPDP Act. They're stored only with the consent tick, shown masked to staff (`+91 98•••••210`), never sent to the KDS or printed on tickets, and kept for 90 days (G-B nightly job blanks `phone` on participants older than that). Name is shown to staff and on tickets.

### 2.4 Guest API (G-B) — all under `GuestAuthGuard`

| Method | Path | Body / result |
|---|---|---|
| GET | `/guest/menu` | Categories → products → variants → modifier groups (QR channel), with **current prices** (happy hour applied, area markup of the table), `available`, `isAlcohol`, image URLs. Reuses the menu service and `order-pricing`. |
| POST | `/guest/rounds` | `{ roundKey, items:[{productId, variantId?, quantity, modifiers:[{groupId, optionId}], note?}] }` → `GuestRoundView`. Validates availability, modifier rules (min/max), limits. Creates the table order if none (DINE_IN, `tableId`, `source GUEST_QR`, `guestSessionId`). Then reads the app-level `routing`: **DIRECT:** `OrdersService.addItems` then `OrdersService.send` as the guest actor, request `CONFIRMED`. **WAITER:** request `PENDING`, no order lines yet, emits `guest.request.new`. Errors: `ITEM_UNAVAILABLE {productIds}`, `MODIFIER_RULE`, `ROUND_TOO_LARGE`, `SESSION_CLOSED`, `GUEST_ORDERING_OFF`. |
| DELETE | `/guest/rounds/:id` | Cancel own PENDING round → `CANCELLED`. (Lines already sent are cancelled by staff only, using the existing void + approval.) |
| GET | `/guest/order` | `GuestOrderView` (2.5) |
| POST | `/guest/service-requests` | `{ type: 'CALL_WAITER' \| 'BILL' }` → `ServiceRequest`. `BILL` = checkout on waiter tables. |
| POST | `/guest/checkout` | `{ mode: 'WAITER' \| 'ONLINE' }`. `WAITER` creates a `BILL` service request (one open at a time; repeat taps return the same one) and returns `{ mode:'WAITER', requestId }`. `ONLINE` returns `501 NOT_AVAILABLE` in this phase (placeholder, Q-2). |
| POST | `/guest/age-confirm` | Sets `ageConfirmedAt`; required before any `isAlcohol` line when `ageGate` is on (`403 AGE_NOT_CONFIRMED`). |

### 2.5 Guest-facing status (G-B, derived — no new columns)

Item state, in priority order:

| State | When |
|---|---|
| `WAITING_WAITER` | Line comes from a PENDING request |
| `SENT` | Line `SENT`, ticket `NEW` |
| `COOKING` | Ticket `PREPARING` |
| `READY` | Ticket `READY` |
| `SERVED` | Ticket `SERVED` or line `SERVED` |
| `CANCELLED` | Line `VOIDED` or request rejected |

The ticket for a line is found through `Ticket.items[].orderItemId`.

```json
GuestOrderView {
  "table": "R4", "status": "OPEN|BILLED|PAID|CLOSED",
  "rounds": [{ "id", "by": "Deepa", "status": "PENDING|CONFIRMED|REJECTED|CANCELLED|EXPIRED", "rejectReason": null,
               "lines": [{ "name", "variant", "modifiers": ["On the rocks"], "qty", "lineTotal", "state", "updatedAt" }] }],
  "totals": { "subtotal", "discount", "serviceCharge", "tax", "roundOff", "grandTotal", "paid", "due" },
  "checkout": { "mode": "WAITER|ONLINE|BOTH", "requested": false }
}
```

Totals come from the existing order view, **including** PENDING rounds priced at today's price and marked "estimate" until confirmed.

### 2.6 Realtime (G-C)

- Socket auth also accepts a guest token. The socket joins **only** `table:<tableId>`.
- New staff events (outlet room plus the claiming waiter's user room):
  - `guest.request.new {requestId, table, by, lines, total}`
  - `guest.request.decided {requestId, status}`
  - `service.request.new {id, table, type}`
  - `service.request.updated`
- New guest events, emitted to `table:<id>` with guest-safe payloads only (no staff names, no costs):
  - `guest.order.updated` (full `GuestOrderView`), sent after any change to the order, its lines, its tickets' KDS status, or its payments
  - `guest.session.closed`
- Hook points are a one-line `guestEvents.orderChanged(orderId)` call at the end of the existing mutating paths in `orders.service` (addItems, send, voidItems, move, merge, transfer, bill), `kds.service` (start, bump, recall, served) and `payments.service` (pay, close). It's a no-op when `order.guestSessionId` is null.
- Fallback when the socket is down: the guest app polls `GET /guest/order` every 5 s.

### 2.7 Staff API and permissions (G-B)

New permission `guests.orders.confirm` (group *Guests & displays*):
- Manager and Captain: EDIT. Waiter: EDIT. Cashier: VIEW. Admin: EDIT.
- Added to `common/permissions/catalog.ts` and the persona matrices (G-A), and to `Perm` on the frontend (G-E).

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/guest-requests?status=PENDING` | VIEW | Outlet's open rounds, oldest first; `mine` = rounds the waiter claimed or on tables they serve |
| POST | `/guest-requests/:id/claim` | EDIT | Sets `claimedById`; others see "Ravi is on it" |
| POST | `/guest-requests/:id/confirm` | EDIT | `{ items? }` (waiter edits: remove/qty/notes) → `OrdersService.addItems` (as the waiter, keeping `guestName`) then `send`; sets `order.waiterId` if empty; status `CONFIRMED` |
| POST | `/guest-requests/:id/reject` | EDIT | `{ reason }` → guest sees the reason |
| GET | `/service-requests?status=OPEN` | `sales.orders.take` VIEW | |
| POST | `/service-requests/:id/ack`, `/:id/done` | `sales.orders.take` EDIT | |
| GET / PUT | `/settings/guest` | `admin.settings` VIEW / EDIT | App-level guest configuration (2.1). `PUT` takes `{ ..., verification: { method, newStaticOtp? } }`; never returns the OTP |
| GET | `/tables/:id/guest-pin` | `sales.orders.take` VIEW | `{ pin }` for a seated table in TABLE_PIN mode |
| POST | `/tables/:id/qr/rotate` | `admin.settings` EDIT | New `qrToken`, closes any open session |
| GET | `/tables/qr-sheet?areaId=` | `admin.settings` VIEW | Printable PDF of table QR cards (reuse the invoice PDF renderer) |

**Session lifecycle (G-B):**
- A session opens on the first join.
- It closes when the order is CLOSED, the order is VOIDED with no other open order on the table, the table is set to FREE or CLEANING by staff, or after 6 h idle.
- On close: rotate `qrToken`, mark pending requests EXPIRED, emit `guest.session.closed`.
- Staff moving or merging the order moves the session with it.

### 2.8 Frontend contracts

**Guest app (G-D)**
- Same Flutter project, public route **`/t/:qrToken`** outside `AppShell`, no login. A separate Dio (`guestDioProvider`) uses the guest token. `deviceKey` and the guest token are stored in local storage per table.
- Screens:
  - **Landing:** table, outlet logo, *See menu & order*, *Call a waiter*, *View bill*.
  - **Your details:** name, mobile number (+91 prefix, numeric keypad), consent tick ("Use my number for this order and updates"), *Continue*.
  - **Verify:** code boxes sized to `codeLength` (6 for static OTP, 4 for table PIN). Copy depends on the method: "Enter the code shown on the table card or given by staff" or "Ask your server for this table's 4-digit PIN". Inline errors: "That code doesn't match · 3 tries left", lockout countdown.
  - **Age gate:** shown when `ageGate` is on and the cart has alcohol.
  - **Menu:** category tabs, search, Popular from kiosk featured items, product cards via `pos_product_grid`, modifier sheet via `modifier_rules`.
  - **My cart:** your name, lines, *Place order*. Copy depends on routing: "Your waiter confirms before it goes to the kitchen" or "Goes straight to the kitchen".
  - **Table order:** rounds grouped by person, a state chip per line, live updates.
  - **Bill:** totals, **Ask for the bill** (primary), and **Pay online** (disabled, "Coming soon"). After asking: "Your waiter is bringing the bill".
  - **Done.**
- Theme: the outlet's assigned theme (Pegs & Bottles). Light mode only for v1 (Q-12).
- **Responsive** (see the design board, "Guest screens on desktop and tablet"):
  - **Phone (< 600 px):** the step-by-step journey.
  - **Tablet (600–1023 px):** category chips on top, a two-column menu card grid, and the cart/table order as a side drawer opened from a floating cart button.
  - **Desktop (≥ 1024 px):** three columns, with categories (and counts), menu cards with search and the happy-hour banner, and a right panel switching between *Your cart* and the live *Table order* (with table total, *Ask for the bill*, *Pay online · Coming soon*). The header keeps *Call a waiter*, *View bill* and the guest's name.
  - Details and code screens appear as a centred card on tablet and desktop.
- Age notice and gate use `minAge` from the configuration ("Alcohol is served only to guests 25 and over").

**Staff app (G-E)**
- **Guest orders** screen at `/service/guest-orders`, nav item under Sales, for personas with `guests.orders.confirm`, with a live badge count. On phones, *Guest orders* **replaces *Orders*** in the footer bar for the **Waiter and Captain** personas (`_personaTabs` in `core/shell/mobile_nav.dart`); Orders moves to More. The footer tab shows the same badge. Each card shows table, who, lines, total, age ("2 min"). Actions: *Claim*, *Edit & confirm* (sheet reusing `pos_ticket_panel` lines), *Reject* with reason.
- **Service requests** strip at the top of the same screen ("R4 · Bill please", "B2 · Call waiter"), with Ack and Done.
- **Floor plan:** table badges for QR active, pending round and bill asked. In TABLE_PIN mode, a seated table's card shows its PIN.
- **Settings › Feature configuration › Guest ordering** (admin): on/off; **Routing** as a two-option control, *Direct to kitchen* / *Via waiter*, with one line explaining each; **Verification** as *Static OTP* (with masked current code and *Set new code*), *Table PIN*, and *SMS OTP* (disabled, "Coming soon"); age gate, require seated, round expiry, limits, checkout mode.
- **Floor setup:** *Rotate QR*, *Print QR sheet* (no per-table routing).
- **Guest orders cards** show the guest's name and masked mobile number.
- KDS ticket header shows **"QR · R4 · Deepa"** when `source = GUEST_QR`. This is a read-only change to `kds_screen.dart`.

---

## 3. Workstreams

Each agent owns only the files listed here.

### G-A — Data model, guest auth, settings, permissions, seed (backend)
- **Owns:** `prisma/schema.prisma` (guest section and the listed columns), the new migration, `prisma/seed.ts` (guest block: `qr-guest` user, `qrToken` for every table, `GuestConfig` defaults, new permission in matrices), `common/permissions/catalog.ts`, `modules/guest-auth/*` (guard, JWT service, lookup/start/verify controller, verification providers), `modules/guest-config/*` (`GET/PUT /settings/guest`), `.env.example` (`GUEST_JWT_SECRET`).
- **Done when:**
  - the migration applies on a copy of the pilot DB and the seed is idempotent,
  - unit tests pass for: start validation (name, phone, consent, not seated), static OTP right/wrong/locked/expired, table PIN right/wrong, SMS OTP returning `NOT_AVAILABLE`, guard scope, rate limits,
  - the settings API never returns the OTP.

### G-B — Guest ordering, status view, waiter confirmation, sessions (backend)
- **Owns:** `modules/guest/*` (menu projection, rounds, order view, checkout, service requests, session lifecycle job, table PIN generation on seating, 90-day phone clean-up job) and `modules/guest-requests/*` (staff API).
- **Also edits** only the listed hook lines in `orders.service.ts`, `kds.service.ts` and `payments.service.ts`, plus `source`/`guestSessionId`/`guestName` pass-through in order create/addItems DTOs.
- **Done when:** these service specs pass: direct round sends tickets, waiter round waits then confirms, reject, expiry, cancel, totals including pending, status derivation for every ticket state, and session close rotates the token.

### G-C — Realtime, notifications, online payment adapter (backend)
- **Owns:** `modules/realtime/*` (guest socket auth, table room, `guestEvents` service), `modules/notifications/*` (waiter notifications for new rounds and bill requests), `modules/payments/gateway/*` (**interface only**: `PaymentGateway { createIntent(order); verifyWebhook(req) }` plus a `NotConfiguredGateway` that throws `NOT_AVAILABLE`; no provider, no webhook route in this phase) (Q-2).
- **Done when:**
  - a guest socket receives `guest.order.updated` within 2 s of a KDS bump,
  - a staff socket receives `guest.request.new` and `service.request.new`,
  - a guest token cannot join outlet or station rooms.

### G-D — Guest web app (frontend)
- **Owns:** `features/guest/**`, the public route in `core/router` (one `GoRoute` and redirect exemption only), `core/network/guest_dio.dart`.
- Writes a repository interface with **two implementations**: a mock (in-memory, used by widget tests and a `--dart-define=GUEST_MOCK=true` run) and the real HTTP one against contract 2.3–2.5. Wave 3 only checks the real one against the merged backend. G-E does the same for the staff APIs (2.7).
- **Done when:**
  - widget tests pass for: the landing seated vs not seated, the details form (name/phone validation, consent), the code screen (6- and 4-digit, wrong code, lockout), the age gate, the cart and modifier rules, every line state chip, and the rejected round message,
  - it works at 360 px wide,
  - it survives a refresh (rejoins with `deviceKey`).

### G-E — Staff app changes (frontend)
- **Owns:** `features/guest_requests/**`, nav entry in `core/shell/nav_registry.dart` (one item), footer tabs for waiter/captain and the badge in `core/shell/mobile_nav.dart`, staff routes in `core/router` (`/service/guest-orders`, guest settings), `Perm.guestsOrdersConfirm` in `core/auth/permission_keys.dart`, floor plan badges and PIN (`floor_plan_screen.dart`, badge widget only), `features/settings/**` Feature configuration › Guest ordering, floor setup QR actions, KDS header label.
- **Done when:**
  - a waiter on the emulator sees a new round in 2 s and confirms or edits it,
  - the badge count updates,
  - the floor plan shows badges.

### G-F — Integration, end-to-end and QA (planner + test agent)
- **Owns:** `docs/phase-4/INTEGRATION.md`, `backend/test/e2e/guest-ordering.e2e-spec.ts`, the emulator/web walkthrough of the exit test, `docs/phase-4/reports/G-F.md`.
- Runs the full backend and frontend test suites after each merge.

---

## 4. Build order (multi-agent)

| Wave | Runs in parallel | Needs |
|---|---|---|
| 0 | Planner answers Q-1…Q-12 and freezes section 2 | Product owner |
| 1 | **G-A** (schema, auth, seed) · **G-D** (guest UI on mocks) · **G-E** (staff UI shells on mocks) | Section 2 frozen |
| 2 | **G-B** (guest + staff APIs) · **G-C** (realtime, notifications, payment adapter) | G-A merged |
| 3 | G-D and G-E switch from mocks to the real API | G-B and G-C merged |
| 4 | **G-F** end-to-end and exit test on emulator plus phone over HTTPS; fixes go back to owners | All merged |

The planner merges each workstream into `phase-1-foundation` in this order, runs `prisma migrate deploy`, both test suites and the build after each merge, and writes `INTEGRATION.md`.

---

## 5. Non-functional requirements

- **Security:**
  - Guest tokens are a separate secret and scope. A guest can read only their own table's order and never another table, staff names or costs.
  - A guest can create only rounds and service requests.
  - QR tokens are random, unguessable and rotated per session.
  - Rate limits are in 2.3.
- **Speed:** menu ≤ 300 ms from cache; status changes reach guests in ≤ 2 s (socket) or ≤ 5 s (polling).
- **Offline:** guest actions need the network; show "You're offline — we'll retry" and never double-submit a round (client idempotency key `roundKey` → unique on `GuestOrderRequest`).
- **Audit:** waiter confirm, reject and edit are written to the audit log with the before/after lines.
- **Reports:** orders by `source` on the dashboard and in day close (G-B adds the field to report queries).
- **Hosting:** the guest app must be reachable from diners' phones at a public **HTTPS** URL. Today everything runs on localhost (Q-9).

---

## 6. Decisions (answered by the product owner)

**Answered.** Every row below is decided as written in the Recommendation column, except where it says *Answered* (use that answer instead) or *On hold*.

| # | Question | Recommendation |
|---|---|---|
| Q-1 | ~~Who decides *direct to kitchen* vs *via waiter*?~~ | **Answered:** one app-level setting chosen by the administrator in Feature configuration (2.1). No per-area/table override; guests don't choose. |
| Q-2 | ~~Online payment gateway?~~ | **Answered:** placeholder only. A disabled "Pay online · Coming soon" button plus the `PaymentGateway` interface; checkout goes via the waiter. The gateway is integrated in a later phase. |
| Q-3 | Group ordering: shared cart, or each person their own cart into one table bill? Can guests see each other's items? Split the bill per person (the board shows "pay my share")? | Own cart per person, one shared table order everyone can see, rounds labelled by name. Per-person split is a follow-up using the existing split API. |
| Q-4 | How to stop someone outside the venue ordering from a photo of the QR? | Ordering works only when staff have seated the table (status OCCUPIED); before that the menu is read-only. QR rotates after each session. **Table PIN** verification (2.3) also blocks it, because only seated guests get the PIN. A static OTP printed on the table card does not. |
| Q-5 | Which waiter gets a table's guest orders? The app has no table-to-waiter assignment. | v1: alert all waiters and captains on shift in the outlet; first to claim owns the table (`order.waiterId`). Section assignment is a later phase. |
| Q-6 | Can guests cancel or change items after placing? | Cancel a round while it waits for the waiter. After it's sent, only staff can void (existing void + approval). |
| Q-7 | Age gate for alcohol: needed, and what age (21 / 25 by state)? | On, with the age set per outlet; staff check ID at the table. |
| Q-8 | Tips, service charge and discounts shown to guests? | Show service charge and tax as the bill does. Tips only with online payment. No guest discounts. |
| Q-9 | Public URL/domain and hosting for the guest web app (HTTPS needed on phones). | **On hold.** Build and test on the local network/emulator; the guest app reads its API base URL from config so hosting can be added without code changes. Needed before the pilot. |
| Q-10 | ~~Guest identity?~~ | **Answered:** name and mobile number are required at scan, verified by static OTP or table PIN; SMS OTP is a placeholder behind the provider interface (2.3). |
| Q-13 | Where is the static OTP shown to guests: printed on the table QR card, told by staff, or on a menu board? | **On hold.** The QR sheet leaves the OTP off for now; staff tell guests the code. Revisit before the pilot. |
| Q-14 | One mobile number at several tables, or the same person rejoining from another phone? | Allow it; each phone is its own participant, same number is fine. |
| Q-11 | If guests leave without checking out: who closes the order? | Unchanged. Staff close it from POS. The session closes when the order closes. |
| Q-12 | Languages (Tamil, Hindi) and dark mode for the guest app in v1? | English and light mode in v1. Labels go through the existing localisation keys so languages can be added without code changes. |

**Items not in the request, assumed in scope:** "Call a waiter" button (on the board), live running total, rejected-round message to the guest, round expiry if no waiter acts in 10 min, printable QR sheet, KDS label showing it's a QR order, consent tick and masked phone numbers for personal-data compliance.

**Out of scope for v1:** per-person bill split, loyalty points/feedback (board step 6), WhatsApp receipts, walk-in queue (board step 3), aggregator orders.
