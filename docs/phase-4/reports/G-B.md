# G-B report: guest ordering, staff confirmation, sessions (backend)

## GUEST_EVENTS port contract

G-B uses **G-C's port as is**. `phase4/g-c` is merged into `phase4/g-b`, and G-B has no port of its own.
- Token: `GUEST_EVENTS` (string), from `modules/realtime/guest-events.port.ts`. `RealtimeModule` (global) binds it with `useExisting: GuestEventsService`.
- Interface `GuestEvents`. Every method returns `Promise<void>` and never throws. G-B calls them with `void`.

| Method | G-B calls it when |
|---|---|
| `orderChanged(orderId)` | after every order, KDS and payment mutation (via `GuestHooks`), and after a round is placed, cancelled, rejected or expired, or a service request is made |
| `requestNew(GuestRequestEventInput)` | a WAITER-routed round is placed (`requestId, tenantId, outletId, table, by, phone, lines[{name,variant,modifiers,qty,lineTotal,note}], total, claimedById:null`) |
| `requestDecided({requestId, outletId, status, claimedById})` | claim (status `PENDING` with `claimedById`), confirm, reject, guest cancel, TTL expiry |
| `serviceRequestNew` / `serviceRequestUpdated` (`ServiceRequestEventInput`) | guest CALL_WAITER/BILL/checkout; staff ack/done |
| `sessionClosed(sessionId, tableId)` | a session is closed |

- **View builder:** in `onModuleInit`, `GuestModule` calls `GuestEventsService.registerViewBuilder({ build: orderId => GuestOrderViewService.build(orderId) })`. That view has `mine: false`.
- **Notifications:** G-B creates none. G-C's `requestNew` and `serviceRequestNew` create them.

## Files

**New in `backend/src/modules/guest/`:**
- `guest-core.module.ts` (global): repository, lifecycle and hooks.
- `guest.repository.ts`: the only Prisma access for G-B.
- `guest-hooks.service.ts`: `orderChanged`, `orderMerged` and `tableChanged`. They are fire-and-forget and never throw.
- `guest-lifecycle.service.ts`:
  - PIN on seating, and the session moves or closes with the order.
  - On close: QR rotated, PIN cleared, pending rounds EXPIRED, open service requests DONE, `GuestAuthGuard.forget`.
  - Jobs on a 60 s `setInterval` (same approach as the KDS overdue job, off in `NODE_ENV=test`), run with `TenantContext.runAsSystem`:
    - round TTL expiry,
    - closing sessions idle for 6 h,
    - blanking phones older than 90 days, once every 24 h.
- `guest-menu.service.ts`: the QR projection of `MenuService.pos`. It uses the same pricing engine, with the area markup from `OrderLineResolver.context` and happy hour.
- `guest-order-view.service.ts`, `guest-status.ts`: GuestOrderView and the derived line states.
- `guest-ordering.service.ts`, `guest.controller.ts`, `dto/guest.dto.ts`, `guest.module.ts`.
- `guest-round.types.ts`: round snapshot and the staff row shapes.
- `guest.service.spec.ts`.

**New in `backend/src/modules/guest-requests/`:** controller, service, DTO and module.

**Edited:**
- `orders.service.ts`:
  - `@Optional() GuestHooks` with hook calls in create, addItems, send, bill, voidItems, voidOrder, move, merge (`orderMerged`) and transferItems.
  - `source`/`guestSessionId` on create. `waiterId: null` is now allowed.
  - A `GUEST_QR` create may claim an OCCUPIED table that has no order.
  - `guestRequestId`/`guestName` on lines, and `guestName` on the KOT ticket items JSON.
- `dto/order.dto.ts`: internal-only fields with no validators, so HTTP rejects them.
- `order-view.ts`: adds `source` and `items[].guestName`.
- `orders.module.ts`: exports `OrderLineResolver`.
- `kds.service.ts` (hook), `kds-view.ts` and `kds.repository.ts`: the ticket payload now has `order.source`, `order.guestName` and `items[].guestName`.
- `payments.service.ts`: hooks after pay and close.
- `floor.service.ts`:
  - `GET /tables` adds `guestPin` (only when seated and in TABLE_PIN mode), `pendingRounds` and `billAsked`.
  - The status hook runs on `PATCH /tables/:id/status`.
- `app.module.ts`.

**G-A edits (minimal, additive):** `guest-auth.service.ts`. The lookup now includes `settings.allowGuestCancel`, and the verify response includes `session.ageConfirmedAt`.

## Decisions and deviations
- **Shapes follow G-D/G-E where they differ from the PLAN:**
  - **Staff rows** (`GET /guest-requests` → `{data:[…]}`, and the claim/confirm/reject results):
    - `id, requestId, tableId, tableName, table{id,name}, guestName, by, phoneMasked, status`
    - `lines[{productId, variantId, name, variantName, modifiers[{groupId,optionId,name}], quantity, unitPrice, lineTotal, note, isAlcohol}]`
    - `total, createdAt, expiresAt, claimedById, claimedByName, claimedBy{id,name}, rejectReason`
    - `roundNo` is always null.
  - **Service requests:** ack and done return the updated row.
  - **Guest menu:** `{categories:[{…, products:[{price, basePrice, listPrice, available, isAlcohol, featured, imageUrl, happyHour{label,percent,until}|null, variants, modifierGroups(QR only)}]}], happyHour, markupPercent}`.
  - **GuestOrderView:**
    - Top level: `orderId` and `atTable`.
    - Rounds: `participantId`, `mine` and `createdAt`.
    - Totals: `estimate` and `pendingEstimate`.
    - Lines the staff added appear in a pseudo-round with id `staff`.
- **New route:** `GET /guest/t/:qrToken/menu`, public and read-only.
- **Round error codes:**
  - `ITEM_UNAVAILABLE {productIds}`, `MODIFIER_RULE`, `ROUND_TOO_LARGE`, `SESSION_CLOSED` (409), `GUEST_ORDERING_OFF` (403), `TABLE_NOT_SEATED`, `AGE_NOT_CONFIRMED` (403).
  - Also `ROUND_NOT_FOUND`, `ROUND_NOT_PENDING`, `CANCEL_NOT_ALLOWED`, `REQUEST_NOT_PENDING`, `ALREADY_CLAIMED`, `PIN_NOT_USED`.
- **Rounds are snapshotted.** Each round stores name, price and isAlcohol beside the submitted items. Pending totals in the view are re-priced at today's price through `OrderLineResolver` and the engine.
- **Direct routing:** the round row is created as CONFIRMED, then `addItems` and `send` run as `qr-guest`. If either fails, the row is deleted.
- **Waiter confirm:** the round is set to CONFIRMED before `addItems` and `send` run, which guards against two waiters confirming at once. If they fail, it goes back to PENDING. The audit log records the before and after lines.
- **Claiming** also sets `order.waiterId` when it is empty (Q-5).
- **Session close:** the session closes when the order is CLOSED, the order is VOID with no other open order on the table, or the table goes FREE or CLEANING. A full payment sets CLEANING, so the session ends at PAID, after `guest.order.updated` has been emitted.
- **Moving the order** moves the session and rotates the old table's QR.
- **QR sheet:** `GET /tables/qr-sheet` returns a **printable HTML page**, not a PDF. No QR or PDF library is installed and puppeteer has no Chrome here. Each card carries the guest URL (`GUEST_APP_BASE_URL`, default `http://localhost:8080`) as text and in `data-url`, with no QR image. I avoided an external QR image service because it would leak the table tokens. G-E saves the response bytes as a PDF, so that needs a follow-up.

## Requests
- Planner: add a QR library (for example `qrcode`) so the sheet can embed real QR images or a PDF, and add `GUEST_APP_BASE_URL` to `.env.example`.
- G-E: `/tables/qr-sheet` returns HTML; open it in a browser or print it.
- Reports by `source` (PLAN 5) are not done.

## Tests
- `npx jest`, whole suite run before the spec was added: 39 suites, 316 pass.
- `guest.service.spec.ts`: 29 pass. Covers:
  - a direct round sends tickets; a waiter round waits, then confirm sends; edited confirm; failed send reverts the round; reject; cancel; idempotent roundKey;
  - validation, the age gate, and checkout (WAITER creates one BILL request, ONLINE gives 501);
  - all line states, totals including the pending estimate;
  - session close rotates the token and clears the PIN; close on order CLOSED or table FREE; PIN generation; expiry; phone blanking;
  - a guest of another session cannot read or act.
- `npm run build` is clean, and the Nest application context boots with all DI resolved.

## Untested
- HTTP end to end against a real DB (all specs use mocks).
- Real KDS and payment flows into the guest view.
- Merge and transfer session moves.
- The 6 h idle close in a live run.
- Concurrent confirms.
