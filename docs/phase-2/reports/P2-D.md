# P2-D report: POS, pay and approval UI, data layer, offline queue (frontend)

Status: code written and read through. NOT compiled or run: no Flutter SDK in this environment. Expect a short compile-fix pass when someone runs `flutter analyze` and `flutter test`.

## Files

Data layer (`frontend/lib/features/pos/data/`)
- `pos_models.dart`: `PosMenu` (+ `PosCategory`, `PosProduct`, `PosVariant`, `PosModifierGroup`, `PosModifierOption`, `PosCombo`, `PosPriceRule`, `PosTaxClass`, `PosSettings`), `OrderView` (+ `OrderItemView`, `OrderTotals`, `PaymentView`, `DiscountView`, `TaxLine`, `TableRef`, `WaiterRef`), `OpenOrderSummary`, `SplitShare`, `SplitResult`, `TableView`, `ApprovalView`, `DayCloseTotals` (+ `CountAmount`, `CategoryTotal`, `StaffDiscount`). Request bodies: `CreateOrder`, `AddItem`, `DiscountInput`, `PaymentInput`, `PaymentRequest`, `ApprovalRequest`, `PinApprovalRequest`. Responses: `SendResult`, `PayResult`, `TicketRef`. Wire constants: `OrderTypes`, `OrderStatuses`, `ItemStatuses`, `ApprovalTypes`, `ApprovalStatuses`, `PaymentMethods`.
- `pos_repository.dart`: `PosRepository` (provider `posRepositoryProvider`), one method per 1.4 endpoint used by POS, pay, approvals, tables and reports, plus `menu()` for `GET /menu/pos`. Errors are rethrown as `ApiError`. Also `OrderCreationGateway`, the one-method interface the queue depends on.
- `offline_queue.dart`: `OfflineOrderQueue` (Hive box `offline_orders`, JSON strings), `generateOfflineId()` (UUID v4 from `Random.secure()`), `FlushResult`, `OfflineQueueEntry`. Providers `offlineOrderQueueProvider` (flushes every 30 s) and `offlinePendingCountProvider`. Network failure stops the flush. A server refusal stays in the queue with `lastError` until discarded. Emits `synced` as `(offlineId, OrderView)`.
- `product_usage.dart`: Favourites store (Hive box `pos_usage`, top 12 by tap count), provider `productUsageProvider`.

Presentation (`frontend/lib/features/pos/presentation/`)
- `pos_screen.dart`: `PosScreen({String? orderId, String? tableId})`. Quick start with order-type tabs and a tables grid for dine-in. Order workspace with category rail, search, product grid, ticket (side panel above 1024 px, bottom sheet below). Offline pending screen at `/pos/offline-<id>`. Helper `startPosOrder`.
- `pos_ticket_panel.dart`: ticket lines, totals, action row, `PosTicketActions` callbacks, `nextSeat`.
- `pos_product_grid.dart`: product cards with variant chips, 86 state, combo cards.
- `pos_order_controller.dart`: `PosOrderController` / `posOrderProvider(orderId)` with optimistic `PendingLine`s. Providers `posMenuProvider`, `posTablesProvider`, `openOrdersProvider`, `managerStaffProvider`.
- `pay_screen.dart`: `PayScreen({required String orderId})`. Modes One bill, Split equally (parts 2–8), By seat, By item. Tip chips None / 5% / 10% / Custom. Tenders Cash keypad (quick ₹500 ₹1,000 ₹2,000 Exact), UPI with reference, Card terminal. "Complete seat N" or "Complete payment". Offline: payment blocked with reason.
- `pay_math.dart`: pure `planTender`, tested.
- `pos_format.dart`: Indian digit grouping, `formatRupees`, `formatWire`, `formatClock`, `parseHexColor`, `parseRupeeInput`, `wireMoney`, `roundPaise`.
- `modifier_rules.dart`: pure min/max validation, single-choice swap, modifier price delta.
- `dialogs/dialog_frame.dart`: `PosDialogFrame`, `PosChoiceChip`.
- `dialogs/modifier_sheet.dart`: `showModifierSheet` returns `ModifierSelection`. Seat 1..covers, note, quantity, min/max enforced.
- `dialogs/discount_dialog.dart`: `showDiscountDialog(context, {required OrderView order})` returns `OrderView?`. Percent/flat, whole bill or selected non-liquor items, reasons, approval warning, "Manager enters PIN here" and "Send to manager's phone" (polls `GET /approvals/:id` every 3 s).
- `dialogs/manager_pin_dialog.dart`: `showManagerPinDialog(context, {type, orderId, payload, reason, title})` returns `ApprovalView?`. Manager picked from `/auth/pin/staff`. PIN errors mapped (`PIN_INVALID` attempts left, `PIN_LOCKED`, `APPROVER_NOT_ALLOWED`).
- `dialogs/void_dialog.dart`: `showVoidDialog(context, {required OrderView order})`. Item selection, required reason chips, SENT warning, manager PIN when the user's `sales.void` level is below APPROVE.
- `dialogs/transfer_dialog.dart`: `showTransferDialog(context, {required OrderView order})`. Whole table (move), some items (to a free table), merge (another open order). Table grid with statuses and the seat-size block.

Tests (`frontend/test/pos/`)
- `pos_models_test.dart`: `OrderView.fromJson` (items, modifiers, totals, tax breakdown, payments, number-typed money, null table/waiter), request JSON, menu and table parsing, approval and day-close totals.
- `offline_queue_test.dart`: queue store, flush order, offlineId reuse, network stop, rejection and discard, `synced` and `changes` streams, concurrent flush. Uses real Hive in a temp dir and a fake gateway.
- `format_and_rules_test.dart`: rupee formatting, modifier min/max, toggle rules, discount approval rules.
- `pay_math_test.dart`: tender planning and split share parsing (sums to grand total).

Deleted: `frontend/lib/features/billing/**` (`billing_screen.dart`, `cart_controller.dart`, `payment_dialog.dart`). Nothing under `lib/` or `test/` imports it now. `app_router.dart` already drops the import, so no edit was needed in P2-E's file.

## Requested change: `tableId`

`PosScreen({String? orderId, String? tableId})`. With no order, `tableId` pre-selects Dine-in and, once `GET /tables` has loaded, opens that table's guest prompt (only if the table is free; an occupied table with an order navigates to that order). The route is NOT wired here: `app_router.dart` (P2-E) currently builds `PosScreen()` and `PosScreen(orderId: ...)`. P2-E needs to add `tableId: state.uri.queryParameters['tableId']` to the `/pos` builder to support `/pos?tableId=...`.

## Assumptions to confirm with P2-C / P2-B

1. Mutations not specified in 1.4 (`hold`/`unhold`, `void-items`, `void`, `move`, `merge`, `refund`, `close`, `bill`, `items` PATCH/DELETE) return `OrderView`. `POST /orders/:id/transfer-items` returns the source order. `POST /approvals/:id/decide` returns `ApprovalView`.
2. PATCH `/orders/:id/items/:itemId` sends modifier ids as `modifiers` (1.4 names the key `modifiers`, not `modifierOptionIds`).
3. `GET /orders/open` returns an array of light rows: `id, orderNumber, type, status, table{name}, covers, grandTotal`.
4. `GET /tables` and `GET /orders/split` return a plain array and `{shares}` respectively; `GET /menu/pos` returns the object from 1.4. `POST /reports/z` returns the day-close row with a `totals` key (handled), and `/reports/day-closes` returns rows with `totals`, `businessDate` (handled).
5. Payment method wire values `CASH`, `UPI`, `CARD`. Split modes `EQUAL`, `SEAT`, `ITEMS`. Decision body `{ decision: APPROVED | DECLINED }`.
6. **Change formula conflict.** 1.4 says `changeGiven = tendered − amount`. The POSPay board shows change net of the tip (Paid ₹1,100, change ₹30 for a ₹1,019 share with ₹51 tip). The screen previews change net of the tip and shows the server's `change` after completion. P2-C should confirm which formula the server uses, or 1.4 should be clarified.
7. The `/auth/pin/staff` list is used for manager choice. The server enforces the APPROVE rule (`APPROVER_NOT_ALLOWED`).

## Deviations from the plan

- Money: fields are `String` as on the wire, with numeric `...Value` getters (for example `grandTotalValue`). A `num get amount` getter would collide with the `amount` fields on `PaymentView` and `SplitShare`.
- Whole-order void is not in the UI (only `voidOrder` in the repository). Void approval uses manager PIN only, with no send-to-phone option.
- Shared items (one item split across seats) are not in the by-item UI. Each item goes to one seat.
- Transfer of items to an existing order is not in the UI. It supports a table or a merge.
- The phone-approval poll runs only while the dialog is open. Closing the dialog leaves the approval pending on the server (expires in 15 min).
- Favourites are stored per device.
- Covers cannot be edited after the order is created (no endpoint in 1.4).

## Open items for others

- P2-E: pass `tableId` from the `/pos` query into `PosScreen` (see above). `/pos/:orderId/pay` already maps to `PayScreen(orderId:)`.
- The whole tree is not verified to compile. Run `flutter analyze` and `flutter test test/pos` once the Flutter SDK is available.
- Test coverage is models, queue, pure rules and tender math. No widget tests were written. Modifier sheet min/max is tested through its pure rules.

No git commit was made.
