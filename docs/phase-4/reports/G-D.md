# G-D report — Guest web app (frontend)

## Files
- `frontend/lib/core/network/guest_dio.dart` — `guestDioProvider`, `GuestTokenHolder` (guest bearer, same `AppConfig.apiBaseUrl`, no staff refresh).
- `frontend/lib/core/router/app_router.dart` — one public `GoRoute('/t/:qrToken')` outside `AppShell`; `isGuestPath` exempts it from the login redirect (staff routes unchanged).
- `frontend/lib/features/guest/data/` — `guest_models.dart` (2.3–2.5), `guest_repository.dart` (interface, providers, `GUEST_MOCK`), `http_guest_repository.dart`, `mock_guest_repository.dart`, `guest_store.dart` (Hive box `guest`: deviceKey + token per QR).
- `frontend/lib/features/guest/application/guest_controller.dart` — journey state, cart, idempotent `roundKey`, live + 5 s poll.
- `frontend/lib/features/guest/presentation/` — theme scope (light only, `DensityScope(pos)`), widgets, menu/choices/age gate, cart/table order/bill, entry screens, phone/tablet/desktop layouts.
- `frontend/test/guest/` — 12 tests.

## Decisions
- Guest socket: own Socket.IO link on `/rt` with `auth.token = guestToken` (staff `RealtimeClient` reads the staff token from SessionStore). Poll `GET /guest/order` every 5 s while the socket is down or offline.
- Offline: keeps `placing` and the same `roundKey`; the poll tick retries. Banner "You're offline — we'll retry".
- Cart note sent as `note` on the first item of the round.
- Wide layouts: "View bill" opens the Table order tab (rounds + bill totals + Ask for the bill / Pay online · Coming soon).
- Mock run: `--dart-define=GUEST_MOCK=true`; QR containing `seat` = not seated, `pin` = table PIN (4817), `direct` = direct routing; static OTP 246810; simulated state progress every 4 s.

## Deviations
- Own product cards instead of `pos_product_grid` (design needs steppers, struck happy-hour price). `modifier_rules` and `pos_format` reused.
- Strings are inline English, not l10n keys (arb files are outside G-D scope).
- Rating stars on the thank-you screen omitted (later phase).
- Fallback Pegs & Bottles light token literals in `guest_theme.dart`, used only if no theme is loaded and the staff app is in dark mode.

## Requests to G-A / G-B / G-C
- Lookup: include `minAge` and `allowGuestCancel` in `settings`; `table` as `{id, name, area}`, `outlet` as `{name, logoUrl}`.
- Public read-only menu for unseated tables: `GET /guest/t/:qrToken/menu` (guest menu needs a token otherwise).
- Menu: `basePrice` (pre-happy-hour), `featured`, and optional `happyHour {label, until}`.
- GuestOrderView rounds: add `createdAt`, `participantId`, `mine`; optional `atTable` count.
- `CODE_LOCKED.details.retryAfter` in seconds; `CODE_INVALID.details.attemptsLeft`.
- Verify response: `session.ageConfirmedAt` so a rejoin skips the age gate.
- Socket: accept guest token in `auth.token`.

## Untested
- HTTP repository and guest socket against the real backend (wave 3). Tablet drawer not covered by a widget test. Not run in a browser (no dev servers per rules).
