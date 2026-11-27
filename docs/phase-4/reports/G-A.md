# G-A report: data model, guest auth, settings, permissions, seed

## Files
- `backend/prisma/schema.prisma`: guest section (6 enums, GuestConfig, GuestSession, GuestParticipant, GuestVerification, GuestOrderRequest, ServiceRequest). It also adds `Order.source`/`guestSessionId` (FK, SetNull), `OrderItem.guestRequestId`/`guestName`, and `DiningTable.qrToken`/`guestPin`/`qrEnabled`.
- `backend/prisma/migrations/20261127100000_guest_ordering/migration.sql`: backfills `qrToken` for existing tables, then sets NOT NULL + unique. It also inserts `guests.orders.confirm` and the persona grants, and shifts sortOrder.
- `backend/prisma/seed.ts`: `seedGuestOrdering()` adds the `qr-guest` user, GuestConfig defaults (OTP 246810, bcrypt, only when absent) and `qrToken` on demo tables. The static OTP is printed in the final log line.
- `backend/src/common/permissions/catalog.ts`: new key + persona matrices.
- `backend/src/modules/guest-config/*`: `GET/PUT /settings/guest`, `GuestConfigService.get(tenantId)`.
- `backend/src/modules/guest-auth/*`:
  - lookup/start/verify controller
  - `GuestJwtService`, `GuestAuthGuard` + `GuestRoute()`, `@CurrentGuest()`
  - verification providers, `GuestRateLimiter`, `GuestPinService`, `guest-utils.ts`
- `backend/src/modules/auth/jwt.strategy.ts`: rejects any payload with `kind` (defence in depth; secrets already differ).
- `backend/src/app.module.ts`, `backend/.env.example` (`GUEST_JWT_SECRET`).

## For G-B / G-C
- Import `GuestAuthModule`. It exports `GuestAuthGuard`, `GuestJwtService`, `GuestAuthRepository`, `GuestRateLimiter`, `GuestPinService` and re-exports `GuestConfigModule`.
- Guest routes use `@GuestRoute()` (Public + GuestAuthGuard) and `@CurrentGuest()`, which returns `{kind, sessionId, participantId, tableId, outletId, tenantId}`. The guard sets TenantContext.
- Rate limits: `limiter.consume('placeOrderPerParticipant', participantId)` and `consume('serviceRequestPerSession', sessionId)` throw `429 RATE_LIMITED {retryAfter}`.
- Table PIN: `GuestPinService.generate(tableId)` returns the PIN; `clear(tableId)` removes it.
- Helpers in `guest-utils.ts`: `newQrToken()`, `maskPhone()`, `normalizeIndianMobile()`.
- Config: `GuestConfigService.get(tenantId)` returns the full config. `effectiveCodeLength(cfg)` is in `guest-config.types.ts`.
- After closing a session, `guard.forget(sessionId)` drops the cached session state (otherwise the cache expires within 30 s).

## Decisions and deviations
- `qrToken` has a DB default (22 hex chars), so the existing floor-module table create works unchanged. The app writes 22-char base64url tokens.
- `GuestVerification` also stores `name` and `consentAt`, so the participant is created only after the code is verified.
- An active lock on the table for the same phone or device also blocks `start`, so a guest can't get round the lockout by starting again.
- Extra error codes:
  - `NAME_INVALID`, `PHONE_INVALID`, `DEVICE_KEY_INVALID`
  - `TABLE_NOT_FOUND`, `VERIFICATION_NOT_FOUND`
  - `GUEST_ORDERING_OFF`
  - `STATIC_OTP_INVALID`, `STATIC_OTP_REQUIRED`
  - `GUEST_TOKEN_REQUIRED`, `GUEST_TOKEN_INVALID`, `SESSION_CLOSED`
- Usernames are globally unique, so tenants other than `default` get `qr-guest-<slug>`.
- The lookup response also includes `minAge`, `requireSeated`, `checkout` and `settings.enabled`.
- `PUT /settings/guest` is a partial merge.

## Requests
- Common/tenancy owner: add the guest models with a tenantId to `TENANT_MODELS`. G-A passes tenantId explicitly.
- Add 410/429/501/503 names to `api-error.ts` ERROR_NAMES. Today they show "Error".

## Untested
- The controllers are not tested end to end over HTTP.
- Concurrent session open (row lock `FOR UPDATE`) is not tested under real concurrency.
- The rate limiter is in-memory, so it is per instance.

## Bug fixes after d4fbf04
None to exported code; only specs were added.
