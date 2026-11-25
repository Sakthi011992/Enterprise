# P3-E report: inventory, procurement, recipes, modifier stock

Scope per PLAN.md section 2. Frontend only, branch `phase-1-foundation`. Nothing committed, no branch switch, no git operations. No Flutter toolchain was available, so every file was checked by rereading, not by compiling or running tests.

## Files

Inventory (`frontend/lib/features/inventory/`)
- `data/json_read.dart`: JSON readers shared by the models.
- `data/stock_format.dart`: `formatStockQty`, `parseStockInput`.
- `data/inventory_models.dart`: 1.7 inventory shapes, count, wastage, variance, recipe.
- `data/inventory_repository.dart`: every P3-B inventory route, file upload, providers.
- `data/offline_count_queue.dart`: Hive-backed count line queue, flush, auto-flush.
- `domain/count_rules.dart`: 30% outlier rule and message. `domain/periods.dart`: date helpers.
- `presentation/inventory_screen.dart` and `presentation/tabs/` (stock items, locations, transfers, stock counts, wastage, variance, kegs).
- `presentation/stock_count_screen.dart`, `presentation/stock_item_editor_screen.dart`, `presentation/log_wastage_sheet.dart`, `presentation/inventory_messages.dart`.
- `presentation/widgets/qty_stepper.dart`, `presentation/widgets/stock_status_badge.dart`.

Procurement (`frontend/lib/features/procurement/`)
- `data/procurement_models.dart`, `data/procurement_repository.dart`.
- `domain/grn_math.dart`: line status, totals, preview sentence.
- `presentation/procurement_screen.dart` (four tabs), `presentation/purchase_order_screen.dart`, `presentation/reorder_screen.dart`, `presentation/grn_screen.dart`.
- `presentation/tabs/vendors_tab.dart`, `presentation/tabs/debit_notes_tab.dart`.

Menu (edited or new)
- `frontend/lib/features/menu/presentation/widgets/recipe_editor.dart` (new), shown as a "Recipe" card in `product_editor_screen.dart` (edited).
- `frontend/lib/features/menu/data/menu_repository.dart` (edited): `ModifierOption` gains `stockItemId`, `stockQty`.
- `frontend/lib/features/menu/presentation/modifier_groups_screen.dart` (edited): stock item select and stock qty field per option.

Shell and router (edited)
- `frontend/lib/core/shell/nav_registry.dart`: bar-tabs, kds, ready, availability, inventory, procurement; stock-count no longer a placeholder.
- `frontend/lib/core/router/app_router.dart`: routes for `/tabs`, `/kds`, `/service/ready`, `/menu/availability`, `/inventory`, `/inventory/items/:id`, `/stock-count`, `/procurement`, `/procurement/reorder`, `/procurement/po/:id`, `/procurement/grn/:id`.

Tests (new)
- `frontend/test/shell/nav_filter_test.dart` (rewritten): nav matrices and expected item lists per role, including path inheritance.
- `frontend/test/inventory/stock_format_test.dart`: formatting and parsing cases.
- `frontend/test/inventory/count_rules_test.dart`: outlier boundaries and message.
- `frontend/test/inventory/offline_count_queue_test.dart`: save/replace, per-count flush, offline and 409 keep lines, newer save during flush, single-flight, unreadable row.
- `frontend/test/procurement/grn_preview_test.dart`: line status, totals, design example sentence from a `GrnView` fixture, empty case, unit word.

## Decisions

- Keg display: the design shows "1 keg + 12.4 L", but the plan's section 1.1 rule gives "1 keg + 12400 ml". I followed the plan, so base-unit remainders always show in ml, g or pc.
- Negatives in `formatStockQty` use U+2212 (minus sign), per the plan.
- Count outlier test is `|counted − expected| × 100 > 30 × |expected|`, so exactly 30% is not an outlier and a zero expectation is never an outlier. Cross-multiplication avoids floating-point errors at the boundary.
- Offline count queue: every typed line is written to Hive first, keyed by count and stock item. A flush removes a row only if its raw text is unchanged, so a newer local value saved during the request survives.
- GRN preview is computed on the client (`grn_math.dart`) while the user types. The server preview (`GrnView.preview`) is used when present, and the saved numbers always come from the server.
- GRN unit words come from the first word of the purchase unit name ("Case of 12 bottles" gives "case"). Pluralisation is simple (add "s").
- GRN PUT body is the POST body without `poId`.
- Reorder send groups suggested lines by location, because `reorderRequest` takes one `locationId` per request.
- Recipe save lives inside the `RecipeEditor` card. Scopes with no ingredients are omitted from the save.
- Stock item numeric fields are sent as JSON numbers.
- Modifier option `stockQty` is parsed from its string form, not cast with `as num?`, so a string from the server cannot fail the cast.

## Deviations

- The design's keg display ("1 keg + 12.4 L") is replaced by the plan rule (see Decisions).
- No OCR on the invoice photo. The photo is uploaded and attached only.
- FIFO helper text is shown in the stock item editor. No FIFO costing is implemented client-side.
- `StockItemRow` has no `purchaseUnitName`, so hand-added GRN lines use a fallback unit word until the item detail loads.
- GRN preview sentence is produced client-side, not from the server text.

## Requests for other workstreams

Status checked against disk at the end of this workstream:
- P3-A: `Perm.kdsBump = 'kds.bump'` is present in `core/auth/permission_keys.dart`, and `kds.bump` is in `backend/src/common/permissions/catalog.ts`. Done.
- P3-D: `BarTabsScreen`, `KdsScreen({initialStation})`, `ReadyToServeScreen`, and `AvailabilityScreen` exist. The router previously passed `station:`; I changed it to `initialStation:` to match P3-D.
- Backend, still open: `formatQty` must emit U+2212 for negatives. Modifier options must accept `stockItemId` and `stockQty` as null. `PUT /grns/:id` must accept a body without `poId`.

## Untested

- Nothing has been compiled or run. Every file was reviewed by reading only, including imports and kit constructor names.
- All new tests (stock format, count rules, offline count queue, GRN preview, nav filter) are unrun.
- Runtime behaviour of the Hive queue, the auto-flush timer, and the count screen's debounce has not been exercised.
- Router and navigation have not been checked on a device.
- `stock_item_editor_screen.dart`, `grn_screen.dart`, and `purchase_order_screen.dart` have only had a single read-through for compile errors.
