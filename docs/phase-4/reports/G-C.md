# G-C report — realtime, notifications, payment gateway placeholder

## Tokens and interfaces

All in `backend/src/modules/realtime/guest-events.port.ts` unless noted.

| Token | Bound to | Where |
|---|---|---|
| `GUEST_EVENTS` (`'GUEST_EVENTS'`) | `{ provide: GUEST_EVENTS, useExisting: GuestEventsService }` | `RealtimeModule` (global), exported. G-B just does `@Inject(GUEST_EVENTS) events: GuestEvents`. |
| `GUEST_ORDER_VIEW` (`'GUEST_ORDER_VIEW'`) | nothing (G-B provides) | Optional. `GuestOrderViewBuilder { build(orderId): Promise<GuestOrderView \| null> }`. Because RealtimeModule cannot see providers inside G-B's module, G-B should call `guestEventsService.registerViewBuilder(builder)` in `onModuleInit` (or make the provider visible globally). Without it, `guest.order.updated` carries `{ orderId, changed: true }`. |
| `PAYMENT_GATEWAY` (`'PAYMENT_GATEWAY'`) | `NotConfiguredGateway` | `modules/payments/gateway/payment-gateway.ts`, provided and exported by `PaymentsModule`. |

```ts
interface GuestEvents {
  orderChanged(orderId: string): Promise<void>;           // no-op unless order.guestSessionId
  requestNew(req: GuestRequestEventInput): Promise<void>;  // + waiter notifications
  requestDecided(req: GuestRequestDecidedInput): Promise<void>;
  serviceRequestNew(req: ServiceRequestEventInput): Promise<void>; // + waiter notifications
  serviceRequestUpdated(req: ServiceRequestEventInput): Promise<void>;
  sessionClosed(sessionId: string, tableId: string): Promise<void>;
}
GuestRequestEventInput { requestId, tenantId, outletId, table /*label*/, by /*guest name*/, phone?, lines: GuestRequestLine[], total, claimedById? }
GuestRequestLine { name, variant?, modifiers?, qty, lineTotal?, note? }
GuestRequestDecidedInput { requestId, outletId, status, claimedById? }
ServiceRequestEventInput { id, tenantId, outletId, table, type: 'CALL_WAITER'|'BILL', status?, acknowledgedById? }

interface PaymentGateway { createIntent(orderId: string): Promise<never>; verifyWebhook(req: unknown): Promise<never> }
```

Every method is best effort: errors are logged, never thrown to the caller. Call after commit.

### Events

| Event | Room(s) | Payload |
|---|---|---|
| `guest.order.updated` | `table:<tableId>` | `GuestOrderView` from the builder, else `{ orderId, changed: true }` |
| `guest.session.closed` | `table:<tableId>` | `{ sessionId }` |
| `guest.request.new` | `outlet:<id>` + `user:<claimedById>` if set | `{ requestId, table, by, phone /*masked +91 98•••••210 or null*/, lines:[{name, variant, modifiers, qty, lineTotal, note}], total }` |
| `guest.request.decided` | outlet + claimer | `{ requestId, status }` |
| `service.request.new` | outlet (+ acknowledgedById) | `{ id, table, type }` |
| `service.request.updated` | outlet + acknowledgedById | `{ id, table, type, status }` |

Helpers: `tableRoom(id)`, `tableEvent(tableId, event, payload)` (scope `'table'`, handled by `RealtimeService.publish`), `RealtimeService.emitToTable`, `maskPhone()`.

### Socket auth

Handshake `auth.token`. If the (unverified) payload has `kind:'guest'`, only the guest path runs: verify with `GUEST_JWT_SECRET`, all claims present, `guest_sessions` row for (id, tenantId, tableId) must be `OPEN`; joins only `table:<tableId>`, the `stations` list is ignored. Otherwise the unchanged staff path runs; it now also rejects any payload with a `kind` claim. The gateway has no message handlers, so no client can join further rooms.

## Notifications

`GuestNotificationsService` (notifications module, exported): one `Notification` row per active user assigned to the outlet whose persona holds the key at EDIT (same row shape as the KDS "ready" notice, `userId` set, `permissionKey` null).
- New round: key `guests.orders.confirm`, type `guest_round`, title `New QR order · R4`, body `Deepa · 3 items`, data `{ requestId }`.
- Service request (BILL and CALL_WAITER): key `sales.orders.take`, type `service_request`, title `Bill requested · R4` / `Waiter called · R4`, data `{ serviceRequestId, type }`.

## Files

- `backend/src/modules/realtime/`: `guest-events.port.ts`, `guest-events.service.ts`, `guest-socket-auth.service.ts`, `realtime.gateway.ts`, `realtime.module.ts`, `realtime.service.ts`, `realtime.types.ts`, `socket-auth.service.ts`, `guest-realtime.spec.ts`
- `backend/src/modules/notifications/`: `guest-notifications.service.ts`, `notifications.module.ts`
- `backend/src/modules/payments/gateway/payment-gateway.ts`, `payments.module.ts`

## Decisions / deviations

- Per-user notification rows instead of a `permissionKey` broadcast row, because the broadcast is visible at VIEW (cashiers have VIEW on `guests.orders.confirm`).
- Notifications are raised inside `requestNew` / `serviceRequestNew`, so G-B makes one call.
- Guest socket session check is not cached (once per connection). Existing guest sockets are not kicked when a session closes; they get `guest.session.closed` and the HTTP guard rejects further calls.
- `guest.session.closed` payload is `{ sessionId }` (PLAN gives none).
- `createIntent` takes `orderId` (task brief) rather than an order object.

## Untested

- Live socket.io end-to-end (no server started); the "within 2 s of a KDS bump" check needs G-B's `orderChanged` hooks and G-F.
- The Prisma `userOutlet` recipient query is tested against a mock only.
