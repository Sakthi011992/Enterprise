# P3-D report: bar tabs, KDS, ready list, availability, realtime client, POS hooks (frontend)

Status: written, not compiled or run. No Flutter toolchain was available, so `flutter pub get`, `flutter analyze` and `flutter test` have not been run. Nothing is committed.

## Files

New (owned by P3-D):

- `frontend/lib/core/realtime/realtime_client.dart`: `RealtimeClient` (Socket.IO on `<origin>/rt`, auth `{ token, stations }`, `on(event)` broadcast streams, `connected` ValueListenable, back-off rebuild on refused handshake), `RealtimeEvent`, `RealtimeEvents` (event names), `realtimeUrl`, `reconnectDelay`, `realtimeClientProvider`, `realtimeEventProvider` (family, for `ref.listen`).
- `frontend/lib/core/realtime/offline_poller.dart`: `OfflinePoller` (runs a refresh every interval only while `connected` is false).
- `frontend/lib/features/tabs/data/tabs_models.dart`: `TabView`, `TabsPage`, `TabCounts`, `TabCloseResult`, `LockerView`, `LockerEvent`, `TabPerson`, status and enum constants, request bodies (`OpenTabRequest`, `TabEditRequest`, `LockerCreateRequest`, `LockerEditRequest`).
- `frontend/lib/features/tabs/data/tabs_repository.dart`: `TabsRepository`, `tabsRepositoryProvider`, one method per tab and locker endpoint in PLAN 1.7.
- `frontend/lib/features/tabs/domain/tab_rules.dart`: `validateOpenTab`, `OpenTabDraft`, `TabField`, `personaLimitWarning`, `tabLimitReachedMessage`, `tabErrorMessage`, `linkTypeLabel`, `isoDate`, `shortDate`, `tabNoSecurityApprovalType`.
- `frontend/lib/features/tabs/presentation/bar_tabs_screen.dart`: `BarTabsScreen` (`/tabs`).
- `frontend/lib/features/tabs/presentation/open_tab_dialog.dart`: `showOpenTabDialog`, `showEditTabDialog`, `TabLinkFields`.
- `frontend/lib/features/tabs/presentation/locker_dialogs.dart`: `showStoreBottleDialog`, `showServeBottleDialog`, `showEditLockerDialog`, `showRemoveLockerDialog`.
- `frontend/lib/features/tabs/presentation/tabs_providers.dart`: `tabsPageProvider` (family by bartender), `lockersProvider`.
- `frontend/lib/features/kds/data/kds_models.dart`: `KdsTicket`, `KdsItem`, `KdsOrderRef`, `KdsBoard` (with `clockOffset`), `KdsAllDayRow`, `ReadyItem`, `ReadyLine`, `KdsStation`, `KdsStatuses`.
- `frontend/lib/features/kds/data/kds_repository.dart`: `KdsRepository`, `kdsRepositoryProvider`.
- `frontend/lib/features/kds/domain/kds_rules.dart`: `colourForAge`, `ticketColourAt`, `colourFromWire`, `formatTicketAge`, `readyForLabel`, `avgTicketLabel`, `kdsErrorMessage`, `actionsFor`, `columnFor`, `lastBumped`, `KdsAction`.
- `frontend/lib/features/kds/presentation/kds_providers.dart`: `kdsBoardProvider`, `kdsStationsProvider`, `readyItemsProvider`.
- `frontend/lib/features/kds/presentation/kds_screen.dart`: `KdsScreen({ String? initialStation })` (`/kds`).
- `frontend/lib/features/kds/presentation/ready_to_serve_screen.dart`: `ReadyToServeScreen` (`/service/ready`).
- `frontend/lib/features/menu/presentation/availability_screen.dart`: `AvailabilityScreen` (`/menu/availability`), plus `availabilityProvider` and `AvailabilityItem` in the same file.
- `frontend/test/kds/kds_rules_test.dart`, `frontend/test/kds/realtime_offline_poll_test.dart`, `frontend/test/tabs/tab_view_test.dart`.

Edited (POS integration, all under `features/pos/**`):

- `frontend/lib/features/pos/data/pos_models.dart`: `OrderTabInfo` class; `OrderView.tab` (parsed from `tab`).
- `frontend/lib/features/pos/presentation/pos_ticket_panel.dart`: header badge "Tab T-07 · ₹4,700 / ₹5,000" (warning tone when near limit).
- `frontend/lib/features/pos/presentation/pos_order_controller.dart`: `TAB_LIMIT_REACHED` on add or edit shows the design copy. The change is in `_fail`, which imports `tabLimitReachedMessage`.
- `frontend/lib/features/pos/presentation/pos_screen.dart`: (a) `PosScreen` listens to `menu.item86` and invalidates `posMenuProvider`; (b) the Bar counter quick start shows an "Open tab" button (needs `sales.tab.open` LIMITED) that calls `showOpenTabDialog` and goes to `/pos/<orderId>`.
- `frontend/pubspec.yaml`: `socket_io_client: ^2.0.3` added under dependencies. Nothing else changed.

Not touched: router, nav registry, `permission_keys.dart`, `menu_repository.dart`, `log_wastage_sheet.dart`, backend.

## Decisions

- **Permission key.** Uses `Perm.kdsBump`, which P3-A added. `Perm.salesTabOpen`, `Perm.salesOrdersTake` and `Perm.menuMark86` already existed.
- **Tab approval.** Security NONE opens `showManagerPinDialog` with type `TAB_NO_SECURITY` (payload `{ guestName, tabLimit }`), then posts `approvalId`. The type is a string constant in `tab_rules.dart`.
- **Tab list filters.** One request per bartender filter (`GET /tabs?scope=today&openedById=`). The Open, Near limit and Closed today chips are filtered on the client from `status`, so the list must include CLOSED tabs (see requests).
- **Tab limit and persona limit.** The open and edit forms block submit when the limit is above the persona limit and show "₹10,000 is above your ₹5,000 limit" on the field. Without a persona limit there is no check.
- **Money in bodies.** Sent as two-decimal strings (`tabLimit`, `amountHeld`, `tabLimit` on edit), matching the Phase 2 convention for payments.
- **Realtime.** `realtimeClientProvider` is rebuilt on login or logout and connects once a session exists. Screens use `ref.listen(realtimeEventProvider(name))` for events. KDS and ready list also run `OfflinePoller` (5 s and 10 s), which does nothing while the socket is up. KDS refreshes on `kds.ticket.created` and `kds.ticket.updated`, debounced 250 ms. Ready list refreshes on `kds.ready`.
- **Socket auth.** The token is read from `SessionStore.accessToken` when the socket is built. A refused handshake rebuilds the socket after 1, 2, 4 ... 30 s with the then-current stored token. Routine drops use Socket.IO's own reconnect.
- **Duplicate-free listeners.** `RealtimeClient.on()` binds each event name to the socket once, even when a socket is rebuilt.
- **Age text.** New and Preparing cards show the age from `createdAt` on the server clock (device time plus `KdsBoard.clockOffset`). READY cards show "Ready N min" from `readyAt`. Colour follows the plan: the clock stops at `readyAt`. Thresholds: under 5 min green, 5 to 10 amber, over 10 red.
- **Ready list waiting time.** Computed from the device clock against `readyAt`, because `/kds/ready` has no server time. Overdue is `overdue` from the server, or more than 5 minutes waiting.
- **Recall last.** Recalls the READY ticket with the latest `readyAt` on the active board. SERVED tickets are not in the active view, so they are not candidates.
- **Bar tabs actions.** Open tabs at a seat or table show Close & pay. Queue or unlinked tabs show Move to table, following the design board. Empty tabs also show Void.
- **Availability.** Loads `/products?limit=200` and `/categories` through `dioProvider`, because `MenuProduct` has no `auto86` or station fields and `menu_repository.dart` belongs to P3-E. Toggles through the existing `MenuRepository.set86`. The station is taken from the product's category.
- **Density.** `DensityScope(AppDensity.pos)` wraps KDS, ready list, availability and bar tabs. Dialogs use the default density, as the POS dialogs do.

## Deviations

- **Timer format.** Age text is `m:ss` with unpadded minutes (`0:42`, `11:20`), to match the KDS board copy. The plan's test name says `mm:ss`. The test asserts the board copy.
- **Full screen.** The KDS toggle sets immersive system UI and hides the page header and the all-day panel. It is not a kiosk lock.
- **Locker ml input.** 30, 60 and 90 ml chips plus a custom field, instead of a stepper.
- **Extra screens.** `showEditTabDialog` and the four locker dialogs are not in the plan's named list. They back the Edit, Store, Serve and Remove actions the plan does list.
- **Ready-list station label.** "Ready at the bar · R4" is built from the station code in lower case, so KITCHEN shows "Ready at the kitchen".

## Requests

For **P3-E** (router, nav, wastage):

- Register `/tabs` → `BarTabsScreen()`, `/kds` → `KdsScreen(initialStation: state.uri.queryParameters['station'])`, `/service/ready` → `ReadyToServeScreen()`, `/menu/availability` → `AvailabilityScreen()`.
- `showLogWastageSheet(context)` is called with no named arguments from the availability screen. That is valid against the current signature.

For **P3-C** (backend JSON, all confirmed against the plan's shapes but not against the running code):

- `GET /tabs` must return CLOSED tabs for `scope=today` when `status` is absent. Otherwise "Closed today" is always empty.
- `GET /products` items need `auto86` (boolean) and `isActive`. `GET /categories` items need `station`. The availability screen reads both.
- `POST /tabs` and `PUT /tabs/:id` must accept `tabLimit` and `amountHeld` as two-decimal strings, and `warnAtPercent` as an integer.
- `POST /approvals/pin` must accept `type: "TAB_NO_SECURITY"`.
- `DELETE /locker/:id` takes a JSON body `{ reason }`. Confirm Nest reads it.
- Socket.IO namespace `/rt`, auth via `handshake.auth` (`token`, `stations`), default `/socket.io` path. The client uses the defaults.
- `OrderView` must carry `tab` (`{ id, number, tabLimit, spent, nearLimit }`) on tab orders, per PLAN 1.7.

For **P3-A / lead**:

- None outstanding. `Perm.kdsBump` is present.

## Untested

Nothing has been compiled, analysed or run. Points to check first:

- **socket_io_client 2.x API**, written from memory: `io.io(url, OptionBuilder()...build())`, `OptionBuilder.setTransports`, `disableAutoConnect`, `setAuth`, `Socket.onConnect`, `onDisconnect`, `onConnectError`, `on`, `connect`, `dispose`. Verify each against the resolved package.
- **Dart 3 syntax.** Record iteration `for (final (title, tickets) in [...])` in `kds_screen.dart`. Pattern `if (order.tab case final tab?)` in `pos_ticket_panel.dart`. `switch` expressions and `abstract final class` constants.
- **Widgets.** `SegmentedButton` and `ButtonSegment` (Flutter 3.7+). `SystemChrome.setEnabledSystemUIMode`. `CheckboxListTile` options. The `Wrap` and `Expanded` layout inside `PosDialogFrame` on phones.
- **Behaviour.** The offline switch is covered only by a unit test of `OfflinePoller`, not by a socket or screen test. The KDS and ready refresh loops, the tab-limit error path, and the 86 live refresh have not been exercised.
- **Token expiry.** Socket rebuilds read the stored token. The token is refreshed only on an HTTP 401 (`DioClient`), so an expired token with no HTTP traffic keeps the socket down until the next REST call. Acceptable for pilot, worth a look.

## Tests added

- `frontend/test/kds/kds_rules_test.dart`: `KdsTicket.fromJson` parsing and placement; colour thresholds at edges; colour frozen at `readyAt`; `m:ss` age text; avg label copy; `lastBumped`; `KdsBoard.clockOffset`; KDS error copy.
- `frontend/test/kds/realtime_offline_poll_test.dart`: `OfflinePoller` refreshes only while disconnected; start and stop idempotent; `realtimeUrl`; reconnect back-off.
- `frontend/test/tabs/tab_view_test.dart`: `TabView.fromJson` near-limit from server flag, from percent, and from spend; `securityLabel`; open-tab validation (age, last 4 digits, deposit, house account, persona limit copy, NONE); tab error copy; `isoDate` and `shortDate`.
