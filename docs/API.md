# API Specification

Base URL: `/api/v1` · Auth: `Authorization: Bearer <accessToken>` · Docs: `/api/docs`

All list endpoints accept `?page=1&limit=20&search=<q>` and return:

```json
{ "data": [ ... ], "meta": { "page": 1, "limit": 20, "total": 0, "totalPages": 0 } }
```

## Session payload (Phase 1)

Returned by every successful login (password, OAuth, select-outlet, switch-outlet, PIN login) and by `GET /auth/me` (without tokens):

```json
{
  "accessToken": "…", "refreshToken": "…",
  "user": { "id": "…", "username": "priya", "displayName": "Priya", "email": "…", "features": [] },
  "tenant": { "id": "…", "name": "Your Venue" },
  "outlet": { "id": "…", "name": "Main outlet", "code": "MAIN" },
  "persona": { "id": "…", "key": "manager", "name": "Manager", "homeRoute": "/dashboard" },
  "permissions": { "menu.edit": { "level": "EDIT", "limit": null }, "sales.discount.give": { "level": "LIMITED", "limit": 30 } },
  "outlets": [ { "id": "…", "name": "Main outlet", "code": "MAIN", "persona": { "key": "manager", "name": "Manager" }, "isDefault": true } ],
  "role": "ADMIN"
}
```

`permissions` holds every catalog key (`NONE` when not granted). `role` is legacy: `ADMIN` for the admin persona, `KIOSK` for the kiosk persona, otherwise `USER`. `user.features` is deprecated and goes with the feature-grant tables in Phase 2.

When a user has more than one outlet and none (or several) is default, password login returns instead:

```json
{ "needsOutlet": true, "selectionToken": "…", "outlets": [ … ] }
```

## Auth
| Method | Path | Auth | Body → Response / Notes |
|--------|------|------|-------------------------|
| POST | `/auth/login` | public | `{ username, password }` → session, or `needsOutlet` (see above). 401 `INVALID_CREDENTIALS`; 403 `NO_OUTLET_ACCESS` when the user has no outlet |
| POST | `/auth/select-outlet` | public | `{ selectionToken, outletId }` → session. Token lives 5 minutes. 401 `SELECTION_EXPIRED` |
| POST | `/auth/switch-outlet` | auth | `{ outletId }` → session with new tokens. 403 `NO_OUTLET_ACCESS` |
| POST | `/auth/refresh` | public | `{ refreshToken }` → `{ accessToken }` (keeps tenant, outlet and persona claims) |
| POST | `/auth/logout` | auth | bumps `tokenVersion`, revoking all refresh tokens → `{ success: true }` |
| GET | `/auth/me` | auth | session without tokens |
| POST | `/auth/forgot-password` | public | `{ usernameOrEmail }` → always `{ success: true }`. Reset link expires in 30 minutes. Phase 1 logs the link (`APP_BASE_URL/reset-password?token=…`) |
| POST | `/auth/reset-password` | public | `{ token, newPassword }` (8+ characters, a letter and a digit) → `{ success: true }`. Bumps `tokenVersion`. 400 `RESET_TOKEN_INVALID` |
| GET | `/auth/pin/staff` | public + `X-Device-Key` | → `{ outlet: { id, name }, staff: [ { userId, displayName, personaName } ] }`. 401 `DEVICE_INVALID` |
| POST | `/auth/pin/login` | public + `X-Device-Key` | `{ userId, pin }` (4 digits) → session for the device's outlet. 401 `PIN_INVALID` with `details.attemptsLeft`. After 3 wrong PINs: 423 `PIN_LOCKED` with `details.lockedUntil` (5 minutes). 403 `NO_OUTLET_ACCESS` when the user is not a PIN persona at that outlet |
| POST | `/auth/login-methods/google/token` | public | `{ idToken }` → same session payload as password login |

Access tokens carry `{ sub, username, tenantId, outletId, personaId, personaKey, tokenVersion }`. On every request the live user and outlet assignment are checked, so removing an outlet takes effect immediately.

## Permissions and personas
Levels, lowest to highest: `NONE < VIEW < REQUEST < LIMITED < APPROVE < EDIT`. A route marked `@Can(key, min)` needs the persona to grant `key` at `min` or above.

| Method | Path | Permission | Body → Response / Notes |
|--------|------|------------|-------------------------|
| GET | `/permissions/catalog` | `admin.users` VIEW | `[ { key, group, label, description, limitUnit, sortOrder } ]` |
| GET | `/personas` | `admin.users` VIEW | `[ { id, key, name, description, homeRoute, loginMethod, isSystem, userCount } ]` |
| POST | `/personas` | `admin.users` EDIT | `{ name, copyFromId? }` → persona. Key is a slug of the name. Copying a matrix cannot grant more than the caller holds (403 `PERMISSION_DENIED`) |
| PATCH | `/personas/:id` | `admin.users` EDIT | `{ name?, description?, homeRoute?, loginMethod? }`. 403 `PERSONA_SYSTEM` for the admin persona |
| DELETE | `/personas/:id` | `admin.users` EDIT | 409 `PERSONA_IN_USE` (with `details.userCount`) while users are assigned. 403 `PERSONA_SYSTEM` |
| GET | `/personas/:id/permissions` | `admin.users` VIEW | `[ { key, level, limit } ]` for every catalog key |
| PUT | `/personas/:id/permissions` | `admin.users` EDIT | `{ items: [ { key, level, limit? } ] }`, a full replacement; keys left out become NONE. 400 `LIMIT_NOT_SUPPORTED` when `limit` is set on a key without a limit unit. 400 `UNKNOWN_PERMISSION`. 403 `PERMISSION_DENIED` when a level is above the caller's own. 403 `PERSONA_SYSTEM` |

## Outlets
| Method | Path | Permission | Body → Response / Notes |
|--------|------|------------|-------------------------|
| GET | `/outlets` | auth | all tenant outlets with `admin.settings` VIEW, otherwise only the caller's outlets |
| POST | `/outlets` | `admin.settings` EDIT | `{ name, code, address?, timezone? }`. 409 `OUTLET_CODE_TAKEN` |
| PATCH | `/outlets/:id` | `admin.settings` EDIT | partial, plus `isActive` |

## Devices
| Method | Path | Permission | Body → Response / Notes |
|--------|------|------------|-------------------------|
| GET | `/devices` | `admin.settings` VIEW | `?outletId=` |
| POST | `/devices` | `admin.settings` EDIT | `{ outletId, name, type }` → `{ device, deviceKey }`. The key is shown once (only its sha256 is stored) |
| DELETE | `/devices/:id` | `admin.settings` EDIT | sets `isActive = false` |

Device types: `POS_TABLET`, `KDS`, `TV`, `KIOSK`, `PRINTER`, `PHONE`.

## Notifications
| Method | Path | Notes |
|--------|------|-------|
| GET | `/notifications?unreadOnly=true` | → `{ data: [...], unreadCount }`. Rows for the caller in the current outlet or tenant-wide: addressed to the caller, or sent to a permission the caller holds at VIEW or above |
| POST | `/notifications/:id/read` | |
| POST | `/notifications/read-all` | → `{ success, count }` |

## Users (ADMIN)
Requires `admin.users`. Users are tenant-scoped; deleted users return 404.

| Method | Path | Permission | Body / Notes |
|--------|------|------------|--------------|
| GET | `/users` | `admin.users` VIEW | list (paginated, search). Each user has `displayName`, `phone`, `outlets: [{ outletId, outletName, personaId, personaName, isDefault }]`, `hasPin` |
| POST | `/users` | `admin.users` EDIT | `{ username, email, password, roleName?, displayName?, phone? }`. `roleName` (`ADMIN`, `USER`, `KIOSK`) picks the starting persona (admin, cashier, kiosk) at the first active outlet |
| GET | `/users/:id` | `admin.users` VIEW | |
| PATCH | `/users/:id` | `admin.users` EDIT | `{ email?, displayName?, phone?, isActive?, roleName?, password? }` |
| PATCH | `/users/:id/reset-password` | `admin.users` EDIT | `{ newPassword }`. Bumps `tokenVersion` |
| PATCH | `/users/:id/pin` | `admin.users` EDIT | `{ pin }` (4 digits). 400 `PIN_TOO_SIMPLE` for `0000`, `1111`…`9999`, `1234`, `4321`. Clears any lock |
| PUT | `/users/:id/outlets` | `admin.users` EDIT | `{ items: [ { outletId, personaId, isDefault? } ] }` replaces all assignments; one default (the first item when none is marked). 400 `DUPLICATE_OUTLET`, `DEFAULT_OUTLET_INVALID`, `INVALID_REFERENCE` |
| DELETE | `/users/:id` | `admin.users` EDIT | soft delete (`deletedAt` set, `isActive = false`) |
| GET | `/users/:id/features` | `admin.users` VIEW | deprecated legacy feature grants |
| PUT | `/users/:id/features` | `admin.users` EDIT | deprecated legacy feature grants |

## Products
| Method | Path | Role | Notes |
|--------|------|------|-------|
| GET | `/products` | auth | search, `?isActive=`, paginated |
| GET | `/products/:id` | auth | |
| POST | `/products` | ADMIN | `{ name, description?, price, taxPercentage? }` |
| PATCH | `/products/:id` | ADMIN | partial update |
| PATCH | `/products/:id/status` | ADMIN | `{ isActive }` |
| DELETE | `/products/:id` | ADMIN | soft delete |
| POST | `/products/:id/image` | ADMIN | multipart `file` |
| POST | `/products/import` | ADMIN | multipart `.xlsx` → import summary |
| GET | `/products/import/template` | ADMIN | downloadable template |

## Tax
| Method | Path | Role | Notes |
|--------|------|------|-------|
| GET | `/tax/global` | auth | active global tax |
| PUT | `/tax/global` | ADMIN | `{ percentage }` |
| PATCH | `/tax/products/:id` | ADMIN | `{ taxPercentage|null }` override |

## Orders
| Method | Path | Role | Notes |
|--------|------|------|-------|
| POST | `/orders` | auth | `{ items:[{productId, quantity}] }` — totals computed server-side |
| GET | `/orders` | auth | search by invoiceNumber, date range, paginated |
| GET | `/orders/:id` | auth | full detail incl. items + payments |

## Payments
| Method | Path | Role | Notes |
|--------|------|------|-------|
| POST | `/payments` | auth | `{ orderId, amount, paymentMethod }` → updates order status |
| GET | `/payments/order/:orderId` | auth | payments for an order |
| POST | `/payments/:id/refund` | ADMIN | mark refunded |

## Invoice
| Method | Path | Role | Notes |
|--------|------|------|-------|
| GET | `/invoice/:orderId/thermal` | auth | 80mm printer-friendly HTML |
| GET | `/invoice/:orderId/pdf` | auth | A4 PDF download |

## Reports (ADMIN)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/reports/dashboard` | today orders/revenue/tax, monthly revenue/tax |
| GET | `/reports/top-products?limit=10` | top selling products |
| GET | `/reports/recent-orders?limit=10` | recent orders |

## Error envelope
```json
{ "statusCode": 400, "message": "…", "error": "Bad Request", "code": "PIN_TOO_SIMPLE", "details": {}, "path": "/api/v1/…", "timestamp": "…" }
```

`code` is always present: a stable machine-readable value, or a default derived from the status (for example `FORBIDDEN`). `details` is present only when the error carries extra data. Codes used in Phase 1: `INVALID_CREDENTIALS`, `NO_OUTLET_ACCESS`, `SELECTION_EXPIRED`, `RESET_TOKEN_INVALID`, `DEVICE_INVALID`, `PIN_INVALID`, `PIN_LOCKED`, `PIN_TOO_SIMPLE`, `PERMISSION_DENIED`, `LIMIT_EXCEEDED` (Phase 2), `LIMIT_NOT_SUPPORTED`, `UNKNOWN_PERMISSION`, `PERSONA_SYSTEM`, `PERSONA_IN_USE`, `OUTLET_CODE_TAKEN`, `DUPLICATE_OUTLET`, `DEFAULT_OUTLET_INVALID`, `INVALID_REFERENCE`.
