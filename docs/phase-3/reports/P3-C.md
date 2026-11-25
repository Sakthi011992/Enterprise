# P3-C report: bar tabs, bottle locker, KDS, realtime, orders integration (backend)

Status: code written and reviewed by reading. Nothing compiled or run (no Node toolchain in the sandbox). Not committed.

## Files

New, under `backend/src/modules/`:

- `realtime/`: `realtime.types.ts` (RealtimeEvent exactly as PLAN 1.9, room helpers, event constructors), `realtime.service.ts` (RealtimeService: attach, emitToOutlet, emitToStation, emitToUser, publish), `socket-auth.service.ts` (SocketAuthService), `realtime.gateway.ts` (namespace `/rt`), `realtime.module.ts` (`@Global()`), specs `realtime.service.spec.ts`, `socket-auth.service.spec.ts`.
- `tabs/`: `tabs.module.ts` (TabsModule), `tabs-limit.module.ts` (TabsLimitModule), `tabs-limit.service.ts` (TabsLimitService), `tabs.service.ts`, `tabs.controller.ts` (`/tabs`), `tabs.repository.ts`, `tab-math.ts` (pure), `tab-view.ts` (TabView and LockerView builders), `locker.service.ts`, `locker.controller.ts` (`/locker`), `locker.repository.ts`, `dto/tab.dto.ts`, `dto/locker.dto.ts`, specs `tab-math.spec.ts`, `tabs-limit.service.spec.ts`, `tabs.service.spec.ts`, `locker.service.spec.ts`.
- `kds/`: `kds.module.ts` (KdsModule), `kds.controller.ts` (`/kds`), `kds.service.ts` (includes the overdue interval), `kds.repository.ts`, `kds-math.ts` (pure), `kds-view.ts` (KdsTicket and ReadyItem builders), `dto/kds.dto.ts`, specs `kds-math.spec.ts`, `kds.service.spec.ts`.

Edited:

- `backend/package.json`: `@nestjs/websockets`, `@nestjs/platform-socket.io` (^10.3.0), `socket.io` (^4.7.5). package-lock untouched.
- `orders/orders.service.ts`: constructor gains StockLedgerService, RealtimeService, TabsLimitService. send, voidItems, voidOrder, bill, addItems, updateItem now run through `mutateWithOutbox`: tickets are printed and realtime sent only after commit. `mutateWithTickets` is gone.
- `orders/orders.service.spec.ts`: constructor call and repository mock updated; two tests added (send deducts at station and publishes KDS cards; void reverses the sale and re-sends the original ticket).
- `orders/order-view.ts`: `ViewContext.tab` (optional) and `OrderView.tab` `{ id, number, tabLimit, spent, nearLimit } | null`.
- `orders/orders.repository.ts`: `viewContext` loads the BarTab on the order; new `findOriginalTickets(tx, orderId)`.
- `orders/orders.module.ts`: imports TabsLimitModule.
- `payments/payments.service.ts`: constructor gains TabsLimitService and RealtimeService. A fully settled order calls `tabs.onOrderPaid(tx, orderId, now)` inside the transaction. pay and legacyCreate publish `order.updated` after commit.
- `payments/payments.service.spec.ts`: two mocks added to the constructor call.
- `payments/payments.module.ts`: imports TabsLimitModule.
- `products/products.service.ts`: manual 86 publishes `menu.item86` (only when the state changes).
- `approvals/approval-payload.ts`: `TAB_NO_SECURITY` kind (permission `sales.tab.open`, payload `{ guestName, tabLimit }`, canonical form, validation). `approvals.service.ts`: title added. `approval-payload.spec.ts`: two tests added. The approval DTO needs no change: it validates with `@IsEnum(ApprovalType)`, which P3-A extends.
- `docs/API.md`: section `## Bar tabs, KDS and realtime (Phase 3)`.

## Decisions

1. **Module graph without a cycle.** `TabsLimitModule` holds TabsRepository and TabsLimitService, with no imports. OrdersModule and PaymentsModule import it. TabsModule imports OrdersModule and PaymentsModule, and does not get imported back. No forwardRef.
2. **Tab limit.** `TabsLimitService.enforce(tx, orderId, spentBefore, now)` runs in addItems and updateItem after re-pricing. It throws 409 `TAB_LIMIT_REACHED` `{ tabId, number, limit, spent, attempted }`, and the transaction rolls back. At the warning level it sets `warnedAt` once, creates an `alert` notification for `openedById`, and publishes `tab.nearLimit` after commit.
3. **Realtime scopes.** Station events go to `outlet:<id>:station:<S>` and to `outlet:<id>:station:*`. A KDS screen that wants every station passes `stations: ["*"]`. Outlet room: `order.updated`, `menu.item86`, `stock.low`, `tab.nearLimit`, `kds.ready`. User room: `kds.ready` for the waiter.
4. **Ticket events.** `kds.ticket.created` goes for each new non-cancellation ticket. A void re-sends the original tickets as `kds.ticket.updated`, with the voided lines flagged. Cancellation tickets are printed but not shown as cards (plan).
5. **Stock hooks.** send calls `deductForSentItems` with each line's station (from routing), inside the transaction. Voids call `reverseSale` with the sent line ids. Ledger events are published after commit.
6. **Close flow.** `TabsService.close` bills through `OrdersService.bill` (which prints the bill), then applies a cash deposit as a CASH payment through `PaymentsService.pay`. The tab stays OPEN (order BILLED) until the order is fully paid. Fully paid means `onOrderPaid` closes it.
7. **Open flow.** Checks in the plan order: age, card last four, deposit amount, house account, table link, then `assertWithinLimit` on the requested limit, then (security NONE without APPROVE) the TAB_NO_SECURITY approval. The order and tab are created in one transaction. Tab number: `T-` plus count+1 for the business date, two digits minimum.
8. **KDS transitions.** `transitionError` (pure) returns `KDS_BAD_STATE` or `RECALL_TOO_LATE`. Bump notifies `order.waiterId ?? ticket.createdById` (type `ready`), and emits the card to the station room and `kds.ready` to the user and outlet. Served sets the ticket's SENT lines to SERVED.
9. **Permissions that are OR rules.** `served` and `ready` have no `@Can`. The service checks `sales.orders.take` or `kds.bump` (EDIT for served, VIEW for ready) and throws 403 `PERMISSION_DENIED`. The locker and tab mutations use `sales.tab.open LIMITED`. Close uses `sales.payments.take EDIT`, which the bartender grant has.
10. **All-day totals.** Items on the business day's tickets that are not SERVED and not voided, active or READY. `avgTicketSeconds` is the mean of creation to bump over the day's bumped tickets, 0 when none.
11. **Overdue alert.** `setInterval` every 60 s in `KdsService.onModuleInit`, cleared on destroy, `unref`, skipped when `NODE_ENV === 'test'`. It finds READY tickets bumped more than 5 minutes ago with no `overdueAlertedAt`, for all outlets, and raises one `alert` notification with `permissionKey: 'kds.bump'`.
12. **Socket auth.** SocketAuthService mirrors `JwtStrategy.validate` (purpose, tenant, token version, outlet access, persona permissions). It is not imported from the auth module, because JwtStrategy is not exported and I did not edit `auth/`. If JwtStrategy changes, update this too.
13. **Locker.** Each change writes an event. REMOVE records the remaining ml written off, and `remainingMl` is left as it was. `expired` in the view compares the expiry date with the outlet's business date.
14. **Extra rules not in the plan.** PUT /tabs refuses a linkType change on a tab that sits on a table (409 `TAB_ON_TABLE`). Locker serve after the expiry date returns 409 `LOCKER_EXPIRED`. The tab limit error reports the total before the change as `spent`.

## Deviations from the plan

- `onOrderPaid` lives on `TabsLimitService`, not `TabsService`. `TabsService` needs PaymentsService, so PaymentsService calling it would be a cycle. The plan's wording was `TabsService.onOrderPaid`.
- `OrdersModule` imports `TabsLimitModule`, not `TabsModule`, for the same reason.
- `ApprovalKind` gained `TAB_NO_SECURITY`, which the plan did not name as an approval kind. The plan only mentioned `canonicalPayload` and the DTO.

## Requests (other workstreams and the owner)

- **P3-A:** checked against the current `schema.prisma` and `TENANT_MODELS`: `BarTab.orderId @unique`, `BottleLockerEntry.events`, the Ticket KDS fields (`kdsStatus`, `startedAt`, `readyAt`, `servedAt`, `recalledAt`, `bumpedById`, `overdueAlertedAt`), `ApprovalType.TAB_NO_SECURITY`, and `BarTab`, `BottleLockerEntry`, `Ticket` in `TENANT_MODELS`. No change requested. Regenerate the Prisma client before compiling.
- **P3-A:** `MovementContext.events` and `RealtimeEvent` import are used as written in its stock-ledger service.
- **P3-B:** stock-ledger events (`stock.low`) should go through `RealtimeService.publish` or `emitToOutlet`. Procurement and inventory do not need to change anything for P3-C.
- **P3-D:** socket details: namespace `/rt`, connect with `auth: { token, stations }`, rooms as above, event names as in `docs/API.md`.
- **Owner / main session:** `npm install` for the three socket dependencies. `main.ts` needs no change if Nest picks up the socket.io adapter from `@nestjs/platform-socket.io` automatically. If the gateway does not start, add `app.useWebSocketAdapter(new IoAdapter(app))` there. I did not edit `main.ts`.
- **Owner:** the cash drawer opens for the tab deposit (it is a CASH payment through `pay`). Consider a flag to skip the drawer for `TAB_DEPOSIT`.

## Known gaps

- Tab numbers use count+1 per business date, so two simultaneous opens can collide. A `DocumentCounter` key would fix it.
- The TAB_NO_SECURITY approval is consumed by `assertApproved` before the tab-creation transaction. If the creation then fails, the approval is spent.
- The overdue job has no tenant context and touches all tenants. It relies on the tenant extension passing through when there is no TenantContext.
- Tab close and card pre-auth do not capture or release the card. That is out of scope for P3-C.

## Untested

Everything. Not run here:

- TypeScript compile. Prisma types for BarTab, BottleLockerEntry, KdsStatus and the new Ticket fields need `prisma generate` from P3-A's schema.
- Nest DI graph for the new modules, and the gateway's `afterInit` server type (whether it accepts `.to(room).emit`).
- Prisma queries: `distinct` with `orderBy` on Category, nested `events: { create }` on BottleLockerEntry, `include` on Order (table and waiter), `findUnique` on BarTab through the tenant extension, and assignability of PrismaService to `Prisma.TransactionClient` as a default parameter.
- Jest specs: all new specs and the updated orders, payments and approvals specs.
- Socket handshake against a running server, and KDS latency (target 2 s).
