# P2-B report: menu, settings, floor, hardware APIs, print service, print agent

Status: code written, not compiled or run (no network or Node toolchain in this session). Jest specs written to pass against the contracts. Nothing committed.

## Files

Backend, new (all under `/home/claude/enterprise/backend/src/modules/`):
- `menu/`: `menu.module.ts`, `menu.controller.ts` (`GET /menu/pos`), `menu.service.ts`, `menu.repository.ts`, `menu-time.ts` (outlet-time helper), `menu.service.spec.ts`
- `categories/`: module, controller, service, repository, `dto/category.dto.ts`
- `modifiers/`: module, controller, service, repository, `dto/modifier-group.dto.ts`
- `combos/`: module, controller, service, repository, `dto/combo.dto.ts`
- `price-rules/`: module, controller, service, repository, `dto/price-rule.dto.ts`
- `tax-classes/`: module, controller, service, repository, `dto/tax-class.dto.ts`, `tax-classes.service.spec.ts`
- `outlet-settings/`: module, controller, service, repository, `dto/outlet-settings.dto.ts`
- `floor/`: module, controller (areas, tables, live view, status), service, repository, `dto/floor.dto.ts`
- `printing/`: `printing.module.ts` (`@Global`, exports `PrintService`), `print.service.ts`, `print-renderer.ts`, `print-jobs.service.ts`, `print-jobs.controller.ts`, `printers.service.ts`, `printers.controller.ts`, `printing.repository.ts`, `dto/printing.dto.ts`, `print-renderer.spec.ts`, `print.service.spec.ts`
- `products/variant-defaults.ts` and `variant-defaults.spec.ts`

Backend, edited:
- `modules/products/` (`products.controller.ts`, `products.service.ts`, `products.repository.ts`, `dto/product.dto.ts`): variants, modifier groups, 86, category and tax class fields.
- `app.module.ts`: registers the 9 P2-B modules and P2-C's `ApprovalsModule`, `DayCloseModule`, `CashDrawerModule`.
- `docs/API.md`: new section "Menu, settings, floor and hardware (Phase 2)", placed before the error envelope.

Print agent, new: `print-agent/` (`package.json`, `tsconfig.json`, `src/index.ts`, `src/escpos.ts`, `README.md`).

## Contract notes and decisions

- **Permissions.** `PATCH /products/:id` had a legacy `@Roles('ADMIN')`. I removed it so `menu.edit EDIT` holders (Manager) can edit, as section 1.4 specifies. The other product write routes keep their existing `@Roles` guard.
- **Write verbs.** Partial updates use PATCH (categories, price rules, tax classes, areas, tables). Nested lists are replaced with PUT (`modifier-groups/:id`, `combos/:id`). Printers and station routes read at VIEW and write at EDIT under `admin.settings`.
- **Deletes.** Most deletes are soft (`isActive = false`). The 409 codes from section 1.4 are implemented: `CATEGORY_IN_USE`, `TAX_CLASS_IN_USE`. Added: `AREA_IN_USE`, `TABLE_HAS_OPEN_ORDER`, `TABLE_NAME_TAKEN`.
- **Variants.** `PUT /products/:id/variants` deactivates variants left out instead of deleting them, so past order lines keep their snapshots. Default rule: none marked makes the first the default, two or more is a 400 `VARIANT_DEFAULT_MULTIPLE`.
- **Menu.** 86'd products stay in `GET /menu/pos` with `is86: true`. Inactive rows are excluded. I read "filters inactive/86 flags" as "exclude inactive, flag 86".
- **Menu times.** `priceRules[].endsAt` is the next occurrence of `endTime` in outlet time, returned only while `activeNow`.
- **Table status.** `PATCH /tables/:id/status` refuses FREE or RESERVED on a table with an open order (409 `TABLE_HAS_OPEN_ORDER`). CLEANING is allowed.
- **Live floor view.** `order.openedAt` is the order's `createdAt`. The waiter name comes from `displayName`, falling back to `username`.
- **Print routing.** A station resolves to its routed printer, then the fallback, each only if it is active and in the outlet. If neither works, the ticket is marked FAILED and no job is queued.
- **Retries.** A failed ticket job moves to the fallback printer first, with attempts reset to 0. Otherwise attempts increase, and at 3 the job and ticket are FAILED with an outlet notification (type `alert`, no permission key).
- **Copies.** A bill's `copies` is stored in `payload.copies`. `/print-jobs/next` returns `printer.copies` as the effective count. The agent never repeats the drawer pulse.
- **Stations.** Ticket staff name is the ticket's `createdById`. Outlet time comes from `Outlet.timezone`.
- **Cash drawer.** `openDrawer` logs and returns `null` when the outlet has no receipt printer. A cash payment is not blocked by a hardware gap. `queueBill` throws 409 `NO_RECEIPT_PRINTER`.

## PrintService (for P2-C)

Injected from the global `PrintingModule`, no import needed:
- `queueTicket(ticket)` takes a Ticket row (needs `id, tenantId, outletId, orderId, kind, station, seq, isCancellation, createdAt, createdById, items`). Sets `Ticket.printerId`. Returns the `PrintJob` or `null`.
- `queueBill(orderId, { copies? })` loads the order itself. Uses `grossAmount` per line and the order's totals. Skips VOIDED items.
- `queueReport(dayCloseId)` prints a saved day close.
- `queueReportTotals(outletId, { kind: 'X' | 'Z', totals, cashCounted?, createdAt? })` is an addition: the live X report has no DayClose row. P2-C should use it for X.
- `openDrawer(outletId, reason)`.
- `queueTest(printerId, outletId)` backs the Test button.

Calls take no transaction client. If P2-C wants print jobs to roll back with a failed transaction, that needs a `tx` argument, which I did not add.

## Print agent

- Polls `GET /print-jobs/next` every 2 s with `X-Device-Key`, sends ESC/POS over TCP (port from the job, 5 s timeout), reports the result.
- Config: `API_BASE_URL`, `DEVICE_KEY`.
- Text is 7-bit ASCII. Non-ASCII becomes `?`. The `language` field is stored but not used.
- Not compiled. No runtime dependencies.

## Tests (Jest, not run)

- `print-renderer.spec.ts`: column widths for 58 and 80 mm, amount formatting, two-column layout and truncation, wrapping, outlet-time formatting, a bill whose totals block adds up, discount line only when there is a discount, ticket width and content, cancellation tickets, a Z report with cash variance.
- `print.service.spec.ts`: station routing (primary, fallback, outlet mismatch, nothing usable), `queueTicket` primary and fallback and FAILED paths, job failure rules (reroute, retry, limit).
- `variant-defaults.spec.ts`: default rule and duplicate names.
- `menu.service.spec.ts`: inactive filtering, 86 flag, modifier group filtering, happy-hour `activeNow` and `endsAt`, combo availability, default settings, `nextClockTime` across midnight.
- `tax-classes.service.spec.ts`: components must sum to the rate.

## Dependencies and checks for the lead

- **P2-A.** My code uses the names from section 1.2. Checked against P2-A's current `schema.prisma` (Printer, StationRoute, PrintJob, Ticket, OrderItem, Order, Area, DiningTable, Combo, PriceRule, TaxClass, Category, OutletSettings). Also imports `isWithinSchedule` from `common/pricing/pricing.engine.ts`, which exists. My new tenant models rely on P2-A's loose-create list. Most creates also pass `tenantId` explicitly.
- **P2-C.** `app.module.ts` imports `./modules/day-close/day-close.module` and `./modules/cash-drawer/cash-drawer.module`. Those files did not exist when I checked, so the app will not compile until P2-C creates them. `approvals` already exists.
- **Frontend (P2-D/E).** The endpoint shapes are in `docs/API.md`. The menu payload matches section 1.4, with one addition: `modifierGroupIds` on products is already filtered to active groups.

## Gaps

- Tamil and other non-ASCII printing needs a printer code page, and the agent does not handle it.
- Bills show item lines and totals only, with no payments or tip section. Service charge is not taxed, as section 1.3 notes.
- No Jest run and no `tsc` run. Two Prisma-typed calls depend on P2-A's generated types: `printer.create` and `prisma.product.update` with `ProductUncheckedUpdateInput`.
- The print agent has no tests.

## Memory

Nothing from the user memory snapshot was used. Nothing new to save.
