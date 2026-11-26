# G-E report — staff app (guest ordering)

## Files
- New: `frontend/lib/features/guest_requests/**` (models, `GuestRequestsRepository` + `HttpGuestRequestsRepository` + `MockGuestRequestsRepository`, providers incl. `guestLiveProvider` / `guestBadgeCountProvider`, Guest orders screen, Edit & confirm sheet, reject dialog, footer badge icon, floor badges + QR actions, KDS QR label).
- New: `features/settings/presentation/guest_ordering_settings_screen.dart` (`/settings/guest-ordering`); link button on Settings screen.
- Edited: `permission_keys.dart` (`Perm.guestsOrdersConfirm`), `nav_registry.dart` (Guest orders, Sales), `mobile_nav.dart` (waiter/captain tab + badge), `app_router.dart` (2 routes, isolated block), `floor_plan_screen.dart` (badges, tile height 104→124), `floor_setup_screen.dart` (FloorQrActions card), `kds_screen.dart` (label), `kds_models.dart` (optional `source`/`guestName`), `test/shell/nav_filter_test.dart` (admin matrix gets new key).
- Tests: `frontend/test/guest_requests/` (24 tests). Whole suite: 198 pass.

## Decisions / deviations
- Mock via `--dart-define=GUEST_MOCK=true`; tests override `guestRequestsRepositoryProvider` and `guestLiveProvider`.
- Live: refetch on `guest.request.*` / `service.request.*`; 5 s polling while the socket is down.
- Badge count = pending rounds + unacknowledged service requests. Footer only; side nav (app_shell) has no badge slot — not touched.
- `kds_models.dart` touched (outside listed scope) to read `source`/`guestName` defensively; label "QR · <name>".
- Confirm without edits sends no `items`; with edits sends full edited list.
- Rotate QR is per table in a "Table QR codes" card on floor setup; Print QR sheet saves the PDF via `FilePicker.saveFile` (bytes fetched with auth).
- PIN: one `GET /tables/:id/guest-pin` per seated table (errors -> no chip).

## Requests
- G-B: `GET /guest-requests` rows: `id, tableId, tableName|table{id,name}, by|guestName, phoneMasked, lines|items[{productId, variantId, name, variantName, modifiers[{groupId,optionId,name}], quantity, unitPrice, lineTotal, note, isAlcohol}], total, createdAt, claimedById, claimedByName, roundNo`. Claim/ack return the updated row.
- G-B: KDS ticket `order.source` and `order.guestName` (or `items[].guestName`).
- G-B: add `guestPin`, pending-round count and bill-asked to `GET /tables` to avoid N PIN calls.
- G-A: `GET /settings/guest` should return `verification.hasStaticOtp` (bool) — never the code.
- G-C: emit events to waiters/captains in outlet room (screen only refetches; payload not used).

## Untested
- HTTP repository against a real backend; PDF save on desktop/Android; realtime socket path; emulator 2 s check.
