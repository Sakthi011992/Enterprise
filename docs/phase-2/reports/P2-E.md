# P2-E report: back-office screens, router, nav (frontend)

Status: code written, not compiled or run. No Flutter SDK or Dart toolchain was available, so the files were checked by reading and a bracket-balance pass only. Run `flutter analyze` and `flutter test` before merging.

## What was built

| Route | Screen | Notes |
|---|---|---|
| `/floor` | `FloorPlanScreen` | Live `GET /tables`, area chips, status legend, side panel. Polls every 15 s. Occupied table opens `/pos/:orderId`. |
| `/settings/floor` | `FloorSetupScreen` | Area add/rename/delete. Table add/edit/delete. Drag snaps to a 12 x 8 grid and saves `posX`/`posY`. |
| `/menu` | `ProductsScreen` (existing) | AppBar links to Categories, Modifiers, Combos, Happy hours. Each row has a "Full editor" icon. |
| `/menu/categories` | `CategoriesScreen` | `AppDataTable`. Delete shows a message on `CATEGORY_IN_USE`. |
| `/menu/products/:id` | `ProductEditorScreen` | Details, category, tax class, variants (exactly one default), modifier groups, 86 switch (`menu.mark86`). |
| `/menu/modifiers` | `ModifierGroupsScreen` | Master-detail. Min and max validation. Options replaced on save. |
| `/menu/combos` | `CombosScreen` | Items with product, qty and swap flag. |
| `/menu/happy-hours` | `PriceRulesScreen` | Percent off, category scope, optional end time, "On now" badge. |
| `/orders` | `OrdersScreen` | Replaces `OrderHistoryScreen`. Filters: status, type, payment, date. Detail drawer with reprint, refund and void. Refund and void retry through the manager PIN dialog on `APPROVAL_REQUIRED`. |
| `/settings/tax` | `TaxSettingsScreen` | Four tabs: Tax rules (components must sum to rate), Service charge & rounding, Invoice numbering (with preview), Global tax (legacy card kept). |
| `/settings/hardware` | `HardwareScreen` | Printers table with status and Test. Add/edit printer dialog with LAN IP and port validation. "Can't reach this printer" alert from `lastError`. Station routing table. |
| `/reports/day-close` | `DayCloseScreen` | Live X report. Z close with cash counted, variance, and a force prompt on `OPEN_ORDERS_EXIST`. History table. |
| `/billing` | legacy redirect to `/pos` | Unchanged in the router. |

The router now points `/pos`, `/pos/:orderId` and `/pos/:orderId/pay` at P2-D's `PosScreen` and `PayScreen`. The billing import and the `OrderHistoryScreen` import are gone.

Nav registry: added Floor plan `/floor` (Sales, `sales.orders.take` VIEW), Day close `/reports/day-close` (Sales, `reports.view` LIMITED), Hardware `/settings/hardware` and Floor setup `/settings/floor` (Settings, `admin.settings` VIEW). Bartender now sees 6 items: POS billing, Orders, Floor plan, Menu & products, Stock count, My shifts.

## Files

New, under `frontend/lib/features/`:
- `floor/data/floor_repository.dart`, `floor/domain/table_status.dart`, `floor/presentation/floor_plan_screen.dart`, `floor/presentation/floor_setup_screen.dart`
- `menu/data/menu_repository.dart`, `menu/presentation/{categories,product_editor,modifier_groups,combos,price_rules}_screen.dart`
- `tax/data/tax_repository.dart`, `tax/domain/tax_rules.dart`
- `hardware/data/hardware_repository.dart`, `hardware/domain/printer_rules.dart`, `hardware/presentation/hardware_screen.dart`
- `reports/data/day_close_repository.dart`, `reports/domain/cash_variance.dart`, `reports/presentation/day_close_screen.dart`
- `orders/presentation/orders_screen.dart`

Tests, under `frontend/test/`:
- `shell/nav_filter_test.dart` (updated): bartender 6 items, the four new items hidden from bartender, `/pos/:id/pay` and `/menu/products/:id` resolve to their parents.
- `backoffice/floor_status_test.dart`: status labels and tones, manual statuses, `FloorTable.fromJson`.
- `backoffice/tax_rules_test.dart`: component sums (including float drift), messages, invoice preview `INV/2026-27/000001`.
- `backoffice/printer_and_cash_test.dart`: IPv4 and port rules, cash variance in paise.

Changed:
- `core/router/app_router.dart`, `core/shell/nav_registry.dart`, `features/products/presentation/products_screen.dart` (links only), `features/tax/presentation/tax_settings_screen.dart` (rewritten).
- `features/orders/data/orders_repository.dart`: new methods added. The legacy `create`, `pay`, `history`, `detail`, `thermalUrl` and `pdfUrl` are kept because `features/billing/**` still imports them until P2-D deletes billing.

Deleted: `frontend/lib/features/orders/presentation/order_history_screen.dart`.

## Dependencies on P2-D

Checked against P2-D's files as they stand in the tree.

1. `PosScreen({super.key, this.orderId})` and `PayScreen({super.key, required this.orderId})` match the router.
2. `showManagerPinDialog` is at `features/pos/presentation/dialogs/manager_pin_dialog.dart` and returns `Future<ApprovalView?>`. The orders screen uses `approval.id` as the approval id for refund and void.
3. `PosRepository` and the P2-D models are not used. The floor plan, day close and orders screens use my own repositories with tolerant `fromJson` parsing. P2-D's `PosRepository` already has `tables()`, `xReport()`, `closeDay()` and `dayCloses()` returning `TableView` and `DayCloseTotals`. The planner can switch to them to remove the duplicate `GET /tables` and `GET /reports/x` calls. That needs the P2-D field names, which I did not use.

## Gaps and assumptions to check

- Floor plan "Start order" opens `/pos` with no table id, because `PosScreen` takes only `orderId`. P2-D's quick start must offer the table grid, or the router needs a `tableId` query parameter. This is not wired.
- Response shapes not given in PLAN 1.4 (I assumed a raw array, or `{ data }` / `{ items }`): `GET /areas`, `/categories`, `/modifier-groups`, `/combos`, `/price-rules`, `/tax-classes`, `/printers`, `/station-routes`, `/orders` (list), `/reports/day-closes`, `/products` (list).
- Field names not in the plan: printer `connection`, `host`, `port`, `paperWidth` (58 or 80, mm), `status`, `lastError`. Tax class `components: [{name, rate}]` in the create and update body. Table `shape` values `SQUARE`, `ROUND`, `RECT`. Service charge types `DINE_IN`, `BAR_COUNTER`, `TAKEAWAY`, `DELIVERY`. Rounding `NONE`, `NEAREST_1`, `NEAREST_5`.
- Table edits and drag use `PATCH /tables/:id` with `posX` and `posY`. Area rename uses `PATCH /areas/:id`. Modifier group update uses `PATCH /modifier-groups/:id` with the full option list. Price rule product scope is not editable in the form; the existing `productIds` are kept.
- `GET /orders` list query: `status`, `type`, `payment`, `search`, `from`, `to` (business dates), `limit`.
- Orders drawer shows the refund button when the order has payments, and the void button when it has none. The server still decides.
- Day close: the X report uses `DaySummary.fromJson` with the 1.6 keys. The Z response body is not read.
- `FieldFrame` is not in the `ui.dart` barrel, so I used a local `_Labelled` widget in two files.
- Not implemented: Stock count and My shifts placeholders are unchanged. Kiosk, Users and Devices are unchanged.

## Tests not run

Nothing was run. Expected failures are most likely from the unverified P2-D names above, so check those imports first.
