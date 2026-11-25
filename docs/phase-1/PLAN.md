# Phase 1 — Foundation: detailed implementation plan

Branch: `phase-1-foundation`. Source designs: *Pub ERP UI Design* boards Components, Shell, States, Errors, Login, OutletPicker, Permissions, Users, TabletPIN, Localisation.

Phase 1 turns the single-shop POS into a multi-outlet, persona-based foundation. When it is done:

- A tenant has outlets; every business row belongs to a tenant, and queries can't leak across tenants.
- Users get a **persona per outlet** (Admin, Manager, Cashier, Captain, Waiter, Bartender, Chef, Storekeeper). Each persona has an editable permission matrix with levels and limits.
- Staff sign in with a password (web) or a 4-digit PIN on a registered shared tablet, with lockout.
- Users can reset a forgotten password.
- The Flutter app has a token-based component kit, a responsive shell whose menu is built from permissions, outlet switching, notifications, and translation scaffolding.
- Every existing screen (billing, orders, products, tax, users, dashboard, appearance) still works inside the new shell.

**Exit test:** a Bartender PIN login sees exactly 5 nav items (POS billing, Orders, Menu & products in view-only, Stock count placeholder, My shifts placeholder); an Admin sees everything; all existing screens still work.

---

## 0. Ground rules for every workstream

1. **Stay inside the files you own** (listed per workstream). If you need a change in someone else's file, write it in your report under "Requests for other workstreams" — don't edit it.
2. **No network.** `npm install`, `npx prisma`, `flutter pub get` and `flutter gen-l10n` will not work here. Write code that would compile; don't try to run builds. Reread your files carefully instead: imports, types, null-safety, matching names with this contract.
3. **Follow the contracts in section 1 exactly**: names, paths, JSON shapes, permission keys. Other workstreams code against them in parallel.
4. Match the existing style: NestJS feature modules (controller / service / dto), class-validator DTOs, Swagger decorators; Flutter with Riverpod `Provider`/`StateNotifierProvider`, GoRouter, Dio, Hive, and `context.tokens` for every colour/spacing (no raw colours in widgets except inside the token extension).
5. Do **not** `git commit`. The integrator commits.
6. At the end, write `docs/phase-1/reports/WS-<letter>.md`: files created or changed, what's done, what's stubbed, known risks, requests for other workstreams.

---

## 1. Shared contracts (all workstreams)

### 1.1 Permission catalog

Keys are stable strings. Levels, in order (used for "at least" checks):

`NONE (0) < VIEW (1) < REQUEST (2) < LIMITED (3) < APPROVE (4) < EDIT (5)`

- `REQUEST` = may ask a manager (approval flow comes in Phase 2).
- `LIMITED` = allowed up to `limit` (percent or ₹), or a restricted subset (e.g. X-report only).
- `APPROVE` = may approve others' requests and do it themselves.

| Key | Group | Label | Limit unit |
|---|---|---|---|
| `sales.orders.take` | Sales | Take orders & send KOT/BOT | — |
| `sales.payments.take` | Sales | Take payment & close bill | — |
| `sales.discount.give` | Sales | Give discount | percent |
| `sales.void` | Sales | Void item / bill | — |
| `sales.tab.open` | Sales | Open bar tab | inr |
| `menu.edit` | Menu & stock | Edit menu & prices | — |
| `menu.mark86` | Menu & stock | Mark item out of stock (86) | — |
| `stock.count` | Menu & stock | Stock count & wastage | — |
| `stock.purchaseOrders` | Menu & stock | Purchase orders | — |
| `guests.queue` | Guests & displays | Walk-in queue | — |
| `displays.control` | Guests & displays | Display Control Center | — |
| `reports.view` | Reports | Reports & day close | — |
| `admin.users` | Admin | Users, personas & permissions | — |
| `admin.settings` | Admin | Outlets, tax, devices & settings | — |
| `admin.themes` | Admin | Themes & branding | — |

### 1.2 Default personas (seeded per tenant)

`key / name / loginMethod / homeRoute`:
`admin / Admin / PASSWORD / /dashboard` (isSystem = true, not editable, not deletable) · `manager / Manager / PASSWORD / /dashboard` · `cashier / Cashier / PIN / /pos` · `captain / Captain / PIN / /pos` · `waiter / Waiter / PIN / /pos` · `bartender / Bartender / PIN / /pos` · `chef / Chef / PIN / /menu` · `storekeeper / Storekeeper / PIN / /menu`

Default matrix (level, limit). Anything not listed = `NONE`.

| Key | admin | manager | cashier | captain | waiter | bartender | chef | storekeeper |
|---|---|---|---|---|---|---|---|---|
| sales.orders.take | EDIT | EDIT | EDIT | EDIT | EDIT | EDIT | — | — |
| sales.payments.take | EDIT | EDIT | EDIT | VIEW | — | EDIT | — | — |
| sales.discount.give | EDIT | APPROVE | LIMITED 10 | LIMITED 10 | — | LIMITED 5 | — | — |
| sales.void | EDIT | APPROVE | REQUEST | REQUEST | REQUEST | REQUEST | — | — |
| sales.tab.open | EDIT | EDIT | LIMITED 5000 | LIMITED 5000 | — | LIMITED 10000 | — | — |
| menu.edit | EDIT | EDIT | VIEW | VIEW | VIEW | VIEW | VIEW | VIEW |
| menu.mark86 | EDIT | EDIT | — | EDIT | — | EDIT | EDIT | EDIT |
| stock.count | EDIT | EDIT | — | — | — | EDIT | EDIT | EDIT |
| stock.purchaseOrders | EDIT | APPROVE | — | — | — | — | REQUEST | EDIT |
| guests.queue | EDIT | EDIT | EDIT | EDIT | VIEW | VIEW | — | — |
| displays.control | EDIT | LIMITED | — | — | — | — | — | — |
| reports.view | EDIT | EDIT | LIMITED | — | — | — | — | LIMITED |
| admin.users | EDIT | — | — | — | — | — | — | — |
| admin.settings | EDIT | VIEW | — | — | — | — | — | — |
| admin.themes | EDIT | VIEW | — | — | — | — | — | — |

The backend owns this data in `backend/src/common/permissions/catalog.ts` (WS-A). The frontend mirrors only the keys in `frontend/lib/core/auth/permission_keys.dart` (WS-D).

### 1.3 Data model (Prisma) — owned by WS-A

Add to `schema.prisma` exactly these (field names are a contract):

```prisma
enum AccessLevel { NONE VIEW REQUEST LIMITED APPROVE EDIT }
enum LoginMethod { PASSWORD PIN }
enum DeviceType { POS_TABLET KDS TV KIOSK PRINTER PHONE }

model Tenant {
  id        String   @id @default(uuid())
  name      String
  slug      String   @unique
  isActive  Boolean  @default(true)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  outlets   Outlet[]
  personas  Persona[]
  users     User[]
  @@map("tenants")
}

model Outlet {
  id          String   @id @default(uuid())
  tenantId    String
  tenant      Tenant   @relation(fields: [tenantId], references: [id])
  name        String
  code        String
  address     String?
  timezone    String   @default("Asia/Kolkata")
  isActive    Boolean  @default(true)
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
  userOutlets UserOutlet[]
  devices     Device[]
  @@unique([tenantId, code])
  @@index([tenantId])
  @@map("outlets")
}

model Persona {
  id          String      @id @default(uuid())
  tenantId    String
  tenant      Tenant      @relation(fields: [tenantId], references: [id])
  key         String
  name        String
  description String?
  homeRoute   String      @default("/dashboard")
  loginMethod LoginMethod @default(PASSWORD)
  isSystem    Boolean     @default(false)
  createdAt   DateTime    @default(now())
  updatedAt   DateTime    @updatedAt
  permissions PersonaPermission[]
  userOutlets UserOutlet[]
  @@unique([tenantId, key])
  @@index([tenantId])
  @@map("personas")
}

model Permission {
  key           String  @id
  group         String
  label         String
  description   String?
  limitUnit     String? // "percent" | "inr" | null
  sortOrder     Int     @default(0)
  personaPermissions PersonaPermission[]
  @@map("permissions")
}

model PersonaPermission {
  personaId     String
  persona       Persona     @relation(fields: [personaId], references: [id], onDelete: Cascade)
  permissionKey String
  permission    Permission  @relation(fields: [permissionKey], references: [key])
  level         AccessLevel @default(NONE)
  limitValue    Decimal?    @db.Decimal(12, 2)
  @@id([personaId, permissionKey])
  @@map("persona_permissions")
}

model UserOutlet {
  userId    String
  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  outletId  String
  outlet    Outlet   @relation(fields: [outletId], references: [id], onDelete: Cascade)
  personaId String
  persona   Persona  @relation(fields: [personaId], references: [id])
  isDefault Boolean  @default(false)
  createdAt DateTime @default(now())
  @@id([userId, outletId])
  @@index([personaId])
  @@map("user_outlets")
}

model StaffPin {
  userId         String    @id
  user           User      @relation(fields: [userId], references: [id], onDelete: Cascade)
  pinHash        String
  failedAttempts Int       @default(0)
  lockedUntil    DateTime?
  updatedAt      DateTime  @updatedAt
  @@map("staff_pins")
}

model Device {
  id         String     @id @default(uuid())
  tenantId   String
  outletId   String
  outlet     Outlet     @relation(fields: [outletId], references: [id])
  name       String
  type       DeviceType
  keyHash    String     @unique // sha256 of the device key
  lastSeenAt DateTime?
  isActive   Boolean    @default(true)
  createdAt  DateTime   @default(now())
  @@index([tenantId])
  @@index([outletId])
  @@map("devices")
}

model Notification {
  id        String    @id @default(uuid())
  tenantId  String
  outletId  String?
  userId    String?   // null = for everyone with `permissionKey`
  permissionKey String?
  type      String    // "approval" | "alert" | "device" | "stock" | "info"
  title     String
  body      String?
  data      Json?
  readAt    DateTime?
  createdAt DateTime  @default(now())
  @@index([tenantId, userId, readAt])
  @@map("notifications")
}

model PasswordResetToken {
  id        String    @id @default(uuid())
  userId    String
  user      User      @relation(fields: [userId], references: [id], onDelete: Cascade)
  tokenHash String    @unique
  expiresAt DateTime
  usedAt    DateTime?
  createdAt DateTime  @default(now())
  @@index([userId])
  @@map("password_reset_tokens")
}
```

Changes to existing models:
- `User`: add `tenantId String` (+ relation to Tenant, index), `displayName String?`, `phone String?`, relations `userOutlets UserOutlet[]`, `staffPin StaffPin?`, `resetTokens PasswordResetToken[]`. **Keep `roleId` / `Role` for now** (deprecated; removed in Phase 2) so the users module keeps compiling.
- Add `tenantId String` + `@@index([tenantId])` to `Product`, `GlobalTaxSetting`, `Order`, `ProductImportLog`, `AuditLog`.
- Add `outletId String?` + index to `Order` (nullable in Phase 1; set on new orders when the request has an outlet).
- `username` and `email` stay globally unique in Phase 1.

### 1.4 Tenant scoping — owned by WS-A

- `backend/src/common/tenancy/tenant-context.ts`: an `AsyncLocalStorage<TenantStore>` where `TenantStore = { tenantId?: string; outletId?: string; userId?: string; system?: boolean }`. Exports `TenantContext` with static `get()`, `set(partial)`, `run(store, fn)`, `runAsSystem(fn)`.
- `TenantContextMiddleware` (applied to all routes in `AppModule.configure`) wraps each request in `TenantContext.run({}, next)`.
- `JwtStrategy.validate` (WS-B) calls `TenantContext.set({ tenantId, outletId, userId })`.
- `PrismaService` becomes a factory provider that returns `new PrismaClient().$extends(tenantScope)` cast to `PrismaService`. Keep the class name and import path (`src/prisma/prisma.service.ts`) so existing modules compile unchanged.
- `TENANT_MODELS = ['Outlet','Persona','User','Product','GlobalTaxSetting','Order','ProductImportLog','AuditLog','Device','Notification']`.
- Rule: if the store has `tenantId` and `system !== true`, then for models in `TENANT_MODELS`: add `tenantId` to `where` on `findMany/findFirst/findFirstOrThrow/count/aggregate/groupBy/updateMany/deleteMany`; for `findUnique/update/delete/upsert` verify after the fact or convert to `findFirst` with `{ id, tenantId }` (document which approach you chose); set `data.tenantId` on `create/createMany/upsert.create` when missing. If no `tenantId` in the store (public routes, seed, auth lookups), don't filter.
- Unit tests (`tenant-scope.spec.ts`) with a mocked `query` function.

### 1.5 Auth API — owned by WS-B

All under `/api/v1`. Errors keep the existing filter shape and **add optional `code` and `details`**: `{ statusCode, message, error, code?, details?, path, timestamp }` (WS-B updates `all-exceptions.filter.ts` to pass `code`/`details` from the exception response).

**Session payload** (returned by every successful login, select-outlet, switch-outlet, pin login; and by `GET /auth/me` without tokens):

```json
{
  "accessToken": "…", "refreshToken": "…",
  "user":    { "id": "…", "username": "priya", "displayName": "Priya", "email": "…" },
  "tenant":  { "id": "…", "name": "Your Venue" },
  "outlet":  { "id": "…", "name": "Main outlet", "code": "MAIN" },
  "persona": { "id": "…", "key": "manager", "name": "Manager", "homeRoute": "/dashboard" },
  "permissions": { "menu.edit": { "level": "EDIT", "limit": null }, "sales.discount.give": { "level": "LIMITED", "limit": 30 } },
  "outlets": [ { "id": "…", "name": "Main outlet", "code": "MAIN", "persona": { "key": "manager", "name": "Manager" }, "isDefault": true } ],
  "role": "ADMIN"
}
```
`permissions` contains every catalog key (NONE included). `role` is legacy: `"ADMIN"` when persona key is `admin`, else `"USER"` (keeps old `@Roles` routes working).

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| POST | `/auth/login` | public | `{ username, password }` → session, **or** `{ needsOutlet: true, selectionToken, outlets: [...] }` when the user has >1 outlet and none is default. 401 `code: INVALID_CREDENTIALS`. 403 `code: NO_OUTLET_ACCESS` if no outlets. 403 `code: USE_PIN` is NOT used — password login works for any persona. |
| POST | `/auth/select-outlet` | public | `{ selectionToken, outletId }` → session. `selectionToken` is a JWT (5 min, secret `JWT_ACCESS_SECRET`, claim `purpose: "outlet-select"`). |
| POST | `/auth/switch-outlet` | auth | `{ outletId }` → session (new tokens). 403 `NO_OUTLET_ACCESS`. |
| POST | `/auth/refresh` | public | `{ refreshToken }` → `{ accessToken }` (keeps tenant/outlet/persona claims). |
| POST | `/auth/logout` | auth | → `{ success: true }` |
| GET | `/auth/me` | auth | → session without tokens |
| POST | `/auth/forgot-password` | public | `{ usernameOrEmail }` → always `{ success: true }`. Creates a token (32 random bytes, base64url; store sha256), expires in 30 min, invalidates older unused tokens for that user. Delivery via `PasswordResetNotifier` interface; Phase 1 implementation logs the link `${APP_BASE_URL}/reset-password?token=…` with Nest `Logger`. |
| POST | `/auth/reset-password` | public | `{ token, newPassword }` (min 8, letter + digit) → `{ success: true }`; marks token used, bumps `tokenVersion`. 400 `code: RESET_TOKEN_INVALID` (unknown, used or expired). |
| GET | `/auth/pin/staff` | public + header `X-Device-Key` | → `{ outlet: { id, name }, staff: [ { userId, displayName, personaName } ] }` — active users of the device's outlet whose persona there has `loginMethod = PIN` and who have a PIN set. 401 `code: DEVICE_INVALID`. Updates `device.lastSeenAt`. |
| POST | `/auth/pin/login` | public + `X-Device-Key` | `{ userId, pin }` → session scoped to the device's outlet. Wrong PIN: 401 `code: PIN_INVALID`, `details: { attemptsLeft }`. After 3 consecutive wrong PINs: lock 5 minutes → 423 `code: PIN_LOCKED`, `details: { lockedUntil }`. Success resets the counter. |

JWT access/refresh payload: `{ sub, username, tenantId, outletId, personaId, personaKey, tokenVersion }`. `JwtStrategy.validate` loads the user (`deletedAt null`, active, matching `tokenVersion`), checks the user still has that outlet, loads the persona's permissions (cache per personaId for 30 s in memory), calls `TenantContext.set(...)`, and returns `request.user`:

```ts
interface AuthUser {
  userId: string; username: string;
  tenantId: string; outletId: string; personaId: string; personaKey: string;
  permissions: Record<string, { level: AccessLevel; limit: number | null }>;
  role: 'ADMIN' | 'USER'; // legacy
}
```

### 1.6 Permission enforcement — owned by WS-B

- `@Can(key: PermissionKey, min: AccessLevel = 'VIEW')` decorator (`common/decorators/can.decorator.ts`) + global `PermissionGuard` (`common/guards/permission.guard.ts`) registered after `JwtAuthGuard`. Public routes skip it. Missing `@Can` = any authenticated user.
- `PermissionsService.assertWithinLimit(user, key, value)` throws 403 `code: LIMIT_EXCEEDED` with `details: { limit }` when level is LIMITED and value > limit (used in Phase 2).
- Put `@Can` on existing controllers, keeping `@Roles` too for now: products write → `menu.edit EDIT`, products read → `menu.edit VIEW`; tax write → `admin.settings EDIT`; users → `admin.users`; orders create → `sales.orders.take EDIT`; orders read → `sales.orders.take VIEW`; payments → `sales.payments.take EDIT`; reports → `reports.view LIMITED`; themes admin writes → `admin.themes EDIT`.

### 1.7 Admin APIs — owned by WS-B

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/permissions/catalog` | `admin.users VIEW` | `[ { key, group, label, description, limitUnit, sortOrder } ]` |
| GET | `/personas` | `admin.users VIEW` | `[ { id, key, name, description, homeRoute, loginMethod, isSystem, userCount } ]` |
| POST | `/personas` | `admin.users EDIT` | `{ name, copyFromId? }` → persona (key = slug of name, unique per tenant; copies matrix when `copyFromId`) |
| PATCH | `/personas/:id` | `admin.users EDIT` | `{ name?, description?, homeRoute?, loginMethod? }`; 403 `PERSONA_SYSTEM` on admin |
| DELETE | `/personas/:id` | `admin.users EDIT` | 409 `PERSONA_IN_USE` when users assigned; 403 `PERSONA_SYSTEM` |
| GET | `/personas/:id/permissions` | `admin.users VIEW` | `[ { key, level, limit } ]` for every catalog key |
| PUT | `/personas/:id/permissions` | `admin.users EDIT` | `{ items: [ { key, level, limit } ] }` → same list; 403 `PERSONA_SYSTEM`; 400 `LIMIT_NOT_SUPPORTED` if limit set on a key without `limitUnit`. Clears the permission cache. |
| GET | `/outlets` | auth | admin.settings ≥ VIEW → all tenant outlets; otherwise only the user's outlets |
| POST | `/outlets` | `admin.settings EDIT` | `{ name, code, address?, timezone? }` |
| PATCH | `/outlets/:id` | `admin.settings EDIT` | partial + `isActive` |
| GET | `/devices` | `admin.settings VIEW` | `?outletId=` |
| POST | `/devices` | `admin.settings EDIT` | `{ outletId, name, type }` → `{ device, deviceKey }` (key shown once: 32 random bytes base64url) |
| DELETE | `/devices/:id` | `admin.settings EDIT` | sets `isActive=false` |
| GET | `/notifications` | auth | `?unreadOnly=true` → `{ data: [...], unreadCount }` for the user (userId = me, or permissionKey the user has ≥ VIEW) in the current outlet or tenant-wide |
| POST | `/notifications/:id/read` | auth | |
| POST | `/notifications/read-all` | auth | |
| PATCH | `/users/:id/pin` | `admin.users EDIT` | `{ pin }` 4 digits; reject `0000`,`1111`…`9999`,`1234`,`4321` with 400 `PIN_TOO_SIMPLE`; resets lock |
| PUT | `/users/:id/outlets` | `admin.users EDIT` | `{ items: [ { outletId, personaId, isDefault } ] }` replaces assignments; exactly one default if any |

Users list/detail responses gain `displayName`, `phone`, `outlets: [{ outletId, outletName, personaId, personaName, isDefault }]`, `hasPin`.

### 1.8 Frontend contracts (WS-C, WS-D, WS-E)

**Component kit (WS-C) — `frontend/lib/core/ui/`, one barrel `ui.dart` exporting all.** Other workstreams import `package:pos_billing/core/ui/ui.dart` and use these exact names:

| Widget / API | Signature (named params) |
|---|---|
| `AppButton` | `AppButton({required String label, VoidCallback? onPressed, AppButtonVariant variant = AppButtonVariant.secondary, AppControlSize? size, IconData? icon, bool loading = false})`; variants `primary, secondary, danger, ghost` |
| `AppIconButton` | `AppIconButton({required IconData icon, required String tooltip, VoidCallback? onPressed, int? badgeCount})` |
| `AppTextField` | `AppTextField({required String label, TextEditingController? controller, String? hint, String? errorText, String? helperText, bool obscure = false, TextInputType? keyboardType, ValueChanged<String>? onChanged, ValueChanged<String>? onSubmitted, Widget? prefix, Widget? suffix, bool autofocus = false, Iterable<String>? autofillHints})` |
| `AppSelect<T>` | `AppSelect({required String label, required T? value, required List<AppSelectItem<T>> items, required ValueChanged<T?> onChanged, String? errorText})`; `AppSelectItem(value, label)` |
| `StatusBadge` | `StatusBadge({required String label, StatusTone tone = StatusTone.neutral})`; tones `success, warning, danger, neutral, info` (always shows a word, never colour only) |
| `InlineAlert` | `InlineAlert({required String message, StatusTone tone = StatusTone.danger, String? actionLabel, VoidCallback? onAction})` |
| `AppBanner` | `AppBanner({required String message, StatusTone tone = StatusTone.warning, String? actionLabel, VoidCallback? onAction})` |
| `showAppToast` | `void showAppToast(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction})` |
| `EmptyState` | `EmptyState({required String title, String? message, IconData icon = Icons.inbox_outlined, String? actionLabel, VoidCallback? onAction})` |
| `ErrorState` | `ErrorState({required String message, VoidCallback? onRetry})` ("Couldn't load … Try again") |
| `SkeletonBox` / `SkeletonList` | `SkeletonBox({double? width, double height = 16})`, `SkeletonList({int rows = 6})`; shimmer-free pulse; only appears after 300 ms via `DelayedSkeleton({required Widget child})` |
| `PageHeader` | `PageHeader({required String title, String? breadcrumb, List<Widget> actions = const []})` |
| `AppCard` | `AppCard({required Widget child, EdgeInsets? padding, String? title, List<Widget> actions = const []})` |
| `AppDataTable<T>` | `AppDataTable({required List<AppColumn<T>> columns, required List<T> rows, String? searchHint, ValueChanged<String>? onSearch, List<Widget> filters = const [], Set<T>? selected, ValueChanged<Set<T>>? onSelectionChanged, List<Widget> bulkActions = const [], void Function(T)? onRowTap, bool loading = false, String? error, VoidCallback? onRetry, Widget? empty})`; `AppColumn<T>({required String label, required Widget Function(T) cell, bool numeric = false, double? width})`; horizontal scroll on narrow widths |
| `ConfirmDialog` | `Future<bool> showConfirmDialog(BuildContext context, {required String title, required String message, String confirmLabel = 'Confirm', bool destructive = false})` |
| `PinPad` | `PinPad({required int length, required ValueChanged<String> onCompleted, String? errorText, bool enabled = true})` (digits 0–9, ⌫, 52 px keys) |
| Token extension | `context.ext` → `ExtTokens { Color successSubtle, onSuccessSubtle, warningSubtle, onWarningSubtle, dangerSubtle, onDangerSubtle, neutralSubtle, onNeutralSubtle; double controlSm=36, controlMd=44, controlLg=52; AppDensity density }` resolved from brightness + `DensityScope` |
| `AppControlSize` | enum `sm, md, lg`; default from `DensityScope` (`comfortable` → md, `compact` → sm, `pos` → lg) |
| `DensityScope` | `DensityScope({required AppDensity density, required Widget child})`, `AppDensity { compact, comfortable, pos }` |

Subtle colours (light / dark) from the Components board: successSubtle `#DCFCE7`/`#052E16`, onSuccessSubtle `#14532D`/`#86EFAC`; warningSubtle `#FEF3C7`/`#422006`, onWarningSubtle `#713F12`/`#FDE68A`; dangerSubtle `#FEE2E2`/`#450A0A`, onDangerSubtle `#7F1D1D`/`#FCA5A5`; neutralSubtle `#E4E4E7`/`#27272A`, onNeutralSubtle `#27272A`/`#E4E4E7`. **Do not change `ThemeTokens.fromJson`** (stored themes would fail to parse); these are an extension with fixed defaults.

**Session & permissions (WS-D) — `frontend/lib/core/auth/`:**
- `session.dart`: `class Session { SessionUser user; NamedRef tenant; OutletRef outlet; PersonaRef persona; Map<String, PermissionGrant> permissions; List<OutletAccess> outlets; String role; }` with `fromJson`/`toJson`; `PermissionGrant { AccessLevel level; num? limit; }`; `enum AccessLevel { none, view, request, limited, approve, edit }` with `atLeast(AccessLevel)`.
- `permission_keys.dart`: `abstract class Perm { static const salesOrdersTake = 'sales.orders.take'; … }` for every key in 1.1.
- `session_controller.dart`: `final sessionProvider = StateNotifierProvider<SessionController, SessionState>`; `SessionState { Session? session; bool loading; String? error; String? errorCode; Map<String, dynamic>? errorDetails; OutletChoice? pendingOutletChoice; }`; methods `loginWithPassword`, `selectOutlet`, `switchOutlet`, `loginWithPin`, `forgotPassword`, `resetPassword`, `logout`, `refreshMe`.
- `bool can(WidgetRef ref, String key, [AccessLevel min = AccessLevel.view])` and `final canProvider = Provider.family<bool, (String, AccessLevel)>`.
- `SessionStore` (existing file) gains `saveSession(Map json)`, `session` getter (Map?), `deviceKey` get/set, `pinnedNavIds` get/set. Keep old methods working.

**Navigation registry (WS-D) — `frontend/lib/core/shell/nav_registry.dart`:** `NavItem { String id; String label; IconData icon; String route; String group; String permission; AccessLevel min; bool placeholder; }` and `const navItems = [...]`. WS-E's admin screens are registered here by WS-D with these routes: `/settings/personas` (admin.users VIEW), `/settings/outlets` (admin.settings VIEW), `/settings/devices` (admin.settings VIEW). WS-E exposes `PersonasScreen`, `OutletsScreen`, `DevicesScreen`, and an updated `UsersScreen` with these class names and file paths (section WS-E).

**Routes (WS-D):** `/login`, `/forgot-password`, `/reset-password?token=`, `/select-outlet`, `/pin` (shared tablet), then inside the shell: `/dashboard`, `/pos`, `/orders`, `/menu`, `/users`, `/settings/tax`, `/settings/personas`, `/settings/outlets`, `/settings/devices`, `/settings/appearance` (+ `/themes`, `/themes/:id`), `/stock-count` (placeholder), `/my-shifts` (placeholder), `/dev/components` (component gallery, only in debug). Redirect: not logged in → `/login` (except auth routes and `/pin`); logged in and route not permitted → `persona.homeRoute`.

---

## 2. Workstreams

### WS-A — Data model, migration, tenancy, uploads fix (backend)

**Owns:** `backend/prisma/**`, `backend/src/prisma/**`, `backend/src/common/tenancy/**`, `backend/src/common/permissions/catalog.ts`, `backend/src/modules/uploads/**`, `backend/.gitignore`, root `.gitignore`.

1. Fix `.gitignore` files so only the runtime upload folder is ignored: change `uploads/` to `/uploads/` in `backend/.gitignore`, and `backend/uploads/` stays in the root file.
2. Recreate `backend/src/modules/uploads/`: `storage.interface.ts` (`export const STORAGE_SERVICE = 'STORAGE_SERVICE'`; `interface StorageService { save(buffer: Buffer, originalName: string, folder: string): Promise<string>; remove(url: string): Promise<void>; }`), `local-storage.service.ts` (writes under `UPLOAD_DIR`, returns `${PUBLIC_BASE_URL}/uploads/<folder>/<uuid><ext>`, `remove` ignores missing files), `uploads.module.ts` (`@Global()`, provides/exports `STORAGE_SERVICE` with `useClass: LocalStorageService`). Products use `save` and `remove` exactly like this.
3. Update `schema.prisma` per 1.3.
4. Write migration `backend/prisma/migrations/20261125100000_phase1_foundation/migration.sql` by hand (Postgres):
   - Create enums and new tables with the same names, constraints and indexes Prisma would generate (`@@map` names, `"tenantId"` camel-case quoted columns like the existing migrations — check `20260615090058_init/migration.sql` for the style).
   - Insert default tenant (`name 'Default venue'`, `slug 'default'`) and outlet (`'Main outlet'`, `code 'MAIN'`) using `gen_random_uuid()::text`.
   - Add `tenantId` columns as nullable, backfill with the default tenant id, then `SET NOT NULL`, add FKs and indexes. Add nullable `outletId` to `orders`.
   - Insert the permission catalog (1.1) and the 8 default personas with their matrix (1.2) for the default tenant.
   - Map existing users: role `ADMIN` → `admin` persona at MAIN (`isDefault true`), role `USER` → `cashier` persona at MAIN.
5. `backend/src/common/permissions/catalog.ts`: export `ACCESS_LEVELS` (ordered), `levelAtLeast(a, b)`, `PERMISSION_CATALOG` (key, group, label, limitUnit, sortOrder), `PermissionKey` union type, `DEFAULT_PERSONAS` (key, name, loginMethod, homeRoute, isSystem, matrix). Must match the migration data exactly.
6. Update `prisma/seed.ts`: idempotent — upsert catalog, default tenant, MAIN outlet, personas + matrix from `catalog.ts`, admin user with tenantId + admin persona at MAIN; sample products with tenantId; global tax with tenantId. Also create a demo bartender `bartender1` (password `Bartender@123`, PIN `2580`) at MAIN for the exit test.
7. Tenancy per 1.4: `tenant-context.ts`, `tenant-context.middleware.ts`, `tenant-scope.extension.ts`, updated `prisma.service.ts` (factory + `$connect` on module init via `onModuleInit` hook in `PrismaModule` or in the factory), `prisma.module.ts` exports. Tests: `tenant-scope.extension.spec.ts` (adds where on findMany, sets data on create, skips when no tenant, skips non-tenant models, `runAsSystem` bypass).
8. Report in `docs/phase-1/reports/WS-A.md`. Note in "Requests": AppModule must apply `TenantContextMiddleware` (WS-B owns `app.module.ts`).

### WS-B — Auth, permissions, admin APIs (backend)

**Owns:** `backend/src/modules/auth/**`, `backend/src/modules/users/**`, new `backend/src/modules/personas/**`, `backend/src/modules/outlets/**`, `backend/src/modules/devices/**`, `backend/src/modules/notifications/**`, `backend/src/common/guards/**`, `backend/src/common/decorators/**`, `backend/src/common/filters/**`, `backend/src/app.module.ts`, `backend/.env.example`, and the `@Can` decorator lines on existing controllers (`products`, `tax`, `orders`, `payments`, `reports`, `themes` controllers — decorators and imports only, no logic changes). Also `docs/API.md`.

1. Implement 1.5, 1.6, 1.7 exactly. Import models/types from `@prisma/client` and catalog from `../../common/permissions/catalog` (WS-A writes it; code against the exports listed in WS-A step 5).
2. `JwtStrategy`, `AuthService` (login, selectOutlet, switchOutlet, refresh, logout, me, forgotPassword, resetPassword, pinStaff, pinLogin), `PasswordResetNotifier` interface + `LoggerPasswordResetNotifier`, `DeviceKeyGuard`/helper that hashes `X-Device-Key` (sha256) and finds an active device (use `TenantContext.runAsSystem` for that lookup, then set the store from the device).
3. A `buildSession(userId, outletId)` helper used by every login path; persona permissions as `Record<key, {level, limit}>` including NONE for missing keys.
4. `PermissionsService` (cache, `levelAtLeast`, `assertWithinLimit`, `invalidate(personaId)`), `PermissionGuard`, `@Can`.
5. `AppModule`: import new modules + `UploadsModule` path stays `./modules/uploads/uploads.module`; register guards in order JwtAuthGuard → PermissionGuard → RolesGuard; implement `NestModule.configure` to apply `TenantContextMiddleware` (from `./common/tenancy/tenant-context.middleware`) for all routes.
6. `.env.example`: add `APP_BASE_URL=http://localhost:5173`.
7. Tests (`*.spec.ts`, Jest with mocked Prisma): `permission.guard.spec.ts`, `auth.service.pin.spec.ts` (attempts left 2→1→locked 423, success resets, lock expiry), `auth.service.reset.spec.ts` (expired/used token rejected, tokenVersion bump), `personas.service.spec.ts` (system persona protected, in-use delete 409, limit on non-limit key 400).
8. Update `docs/API.md` with the new endpoints.
9. Report in `docs/phase-1/reports/WS-B.md`.

### WS-C — Component kit, tokens extension, states, translations (frontend)

**Owns:** `frontend/lib/core/ui/**`, `frontend/lib/core/theme/token_ext.dart`, `frontend/lib/l10n/**`, `frontend/l10n.yaml`, `frontend/pubspec.yaml` (add `flutter_localizations: sdk: flutter` and `generate: true` under `flutter:`), `frontend/lib/features/dev/**` (component gallery), `frontend/test/ui/**`.

1. `token_ext.dart`: `ExtTokens`, `AppDensity`, `DensityScope`, `extension ExtTokenContext on BuildContext { ExtTokens get ext; }` (reads `Theme.of(context).brightness` and nearest `DensityScope`, default `comfortable`).
2. Build every widget in the 1.8 kit table with exactly those names/params, using `context.tokens` + `context.ext` only. Buttons: min height from size (36/44/52), visible focus ring using `tokens.color.border.focus`, loading state shows spinner + label ("Saving…" is the caller's label). Text field: label above, error text below in danger colour with an icon, never colour alone. Data table: search box, filter slot, column header row, row hover, selection checkboxes, bulk bar when selection non-empty ("2 selected" + actions), loading → `DelayedSkeleton(SkeletonList)`, error → `ErrorState`, empty → `empty ?? EmptyState(title: 'Nothing here yet')`; wrap in horizontal `SingleChildScrollView` under 720 px.
3. `PinPad`: 3×4 grid (1–9, empty, 0, ⌫), dots row showing entered digits count, calls `onCompleted` at `length`, then clears; shows `errorText` under the dots; supports hardware keyboard digits and Backspace via `Focus`/`KeyboardListener`.
4. `ui.dart` barrel exporting all public widgets and `token_ext.dart`.
5. Translations: `l10n.yaml` (`arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, `output-localization-file: app_localizations.dart`, `nullable-getter: false`), `lib/l10n/app_en.arb` with keys for shell + auth strings (at least: appTitle, signIn, username, password, forgotPassword, invalidCredentials, accountLocked, resetPassword, newPassword, sendResetLink, resetLinkSent, chooseOutlet, enterPin, pinWrongAttemptsLeft (plural with {count}), pinLocked ({minutes}), search, notifications, markAllRead, signOut, switchOutlet, language, darkMode, pinned, nothingHereYet, couldNotLoad, tryAgain, saving, saved, undo). Also `app_ta.arb` and `app_hi.arb` copies with the English text and a `@@locale`, marked `"x-untranslated": true` in each entry's metadata — real translations come later.
6. `frontend/lib/features/dev/component_gallery_screen.dart`: `ComponentGalleryScreen` showing every widget in all variants/states, light and dark, three densities (mirrors the Components and States boards).
7. Widget tests in `frontend/test/ui/` for AppButton (loading disables tap), PinPad (completes at length, backspace), StatusBadge (renders label text), AppDataTable (bulk bar appears on selection). Wrap test widgets with the existing `TokenTheme` and a theme built from `frontend/lib/core/theme` defaults — read `theme_providers.dart`/`app_theme.dart` to find the default token source.
8. Report in `docs/phase-1/reports/WS-C.md`.

### WS-D — Session, routing, shell, auth screens (frontend)

**Owns:** `frontend/lib/core/auth/**`, `frontend/lib/core/shell/**`, `frontend/lib/core/router/app_router.dart`, `frontend/lib/core/storage/session_store.dart`, `frontend/lib/core/network/dio_client.dart`, `frontend/lib/main.dart`, `frontend/lib/features/auth/**`, `frontend/lib/features/admin/presentation/admin_shell.dart` (delete it once the new shell replaces it, and remove its imports), `frontend/test/auth/**`, `frontend/test/shell/**`.

Use the WS-C kit by the names in 1.8 (it's being written in parallel; don't create your own copies).

1. Session layer per 1.8. `AuthRepository` with methods for every 1.5 endpoint; parse errors into `ApiError { int status; String? code; String message; Map<String,dynamic>? details; }` from Dio responses.
2. `DioClient`: keep refresh flow; on refresh failure clear session and signal logout (a `ValueNotifier<bool>` or callback the session controller listens to). Add `X-Device-Key` header for `/auth/pin/*` when a device key is stored.
3. Screens (match the Login, OutletPicker, TabletPIN boards):
   - `login_screen.dart`: username, password (show/hide), "Remember me" not needed; inline error for `INVALID_CREDENTIALS` ("Wrong username or password."), `NO_OUTLET_ACCESS` ("Your account isn't linked to any outlet. Ask your admin."), network error banner; link to Forgot password; link "Use staff PIN" → `/pin` when a device key is stored.
   - `forgot_password_screen.dart` → always shows "If that account exists, we've sent a reset link." after submit.
   - `reset_password_screen.dart` reads `token` query param; validates (min 8, letter + digit, confirm match); handles `RESET_TOKEN_INVALID` ("This link has expired or was already used. Request a new one.").
   - `outlet_picker_screen.dart`: cards per outlet with persona name; selecting calls `selectOutlet` (or `switchOutlet` when already signed in).
   - `pin_login_screen.dart`: if no device key stored → "This tablet isn't set up yet" with a field to paste the device key (saved via SessionStore) ; else staff tiles from `/auth/pin/staff` → tap a tile → `PinPad(length: 4)` → login; show `PIN_INVALID` with attempts left, `PIN_LOCKED` with a countdown to `lockedUntil`.
4. Shell (`core/shell/app_shell.dart`, match the Shell board): top bar = logo, search button showing "Search or jump to… Ctrl K" (opens `CommandPalette` dialog listing permitted nav items, filter as you type, Enter navigates; Ctrl/Cmd+K shortcut), outlet switcher menu (lists `session.outlets`, calls switchOutlet, then go to new persona homeRoute), language menu (English only active; Tamil/Hindi shown disabled "coming soon"), dark mode toggle (reuse `theme_mode_toggle.dart`), notifications bell with unread badge (polls `/notifications?unreadOnly=true` every 60 s) opening `NotificationsPanel` (tabs All / Approvals / Alerts; Mark all read; Approve/Decline buttons shown for type `approval` but disabled with tooltip "Approvals arrive in Phase 2"), account menu (name, persona, Sign out). Side nav = `navItems` filtered by permission, grouped (Pinned, Sales, Menu & stock, Guests & displays, People & money, Settings); a pin icon on hover pins up to 5 items (persisted). Layout: ≥1280 px full side nav; 768–1279 icon rail with tooltips; <768 drawer + top bar menu button. Wrap shell body in `DensityScope` (`pos` for `/pos`, `comfortable` otherwise).
5. `nav_registry.dart` with items: Dashboard `/dashboard` (reports.view LIMITED), POS billing `/pos` (sales.orders.take EDIT), Orders `/orders` (sales.orders.take VIEW), Menu & products `/menu` (menu.edit VIEW), Stock count `/stock-count` (stock.count EDIT, placeholder), My shifts `/my-shifts` (sales.orders.take VIEW, placeholder — every staff persona), Users `/users` (admin.users VIEW), Personas & permissions `/settings/personas` (admin.users VIEW), Outlets `/settings/outlets` (admin.settings VIEW), Devices `/settings/devices` (admin.settings VIEW), Tax `/settings/tax` (admin.settings VIEW), Appearance `/settings/appearance` (admin.themes VIEW). With the default matrix a Bartender sees exactly: POS billing, Orders, Menu & products, Stock count, My shifts → 5 items (exit test). Placeholder screens use `EmptyState(title: 'Coming in a later phase')`.
6. Router per 1.8 using `ShellRoute` for shell pages; `refreshListenable` tied to session changes. Existing screens are mounted as-is: `DashboardScreen`, `BillingScreen` (+ `OrderHistoryScreen` stays separate at `/orders`), `ProductsScreen`, `TaxSettingsScreen`, appearance pages; `/users` → `UsersScreen` (WS-E updates it in place); `/settings/personas|outlets|devices` → WS-E screens. `/dev/components` → `ComponentGalleryScreen` when `kDebugMode`.
7. `main.dart`: add `localizationsDelegates`/`supportedLocales` (`AppLocalizations` from `package:flutter_gen/gen_l10n/app_localizations.dart` — with `generate: true` that is the import path) ; keep the existing overrides.
8. Tests: `test/auth/session_test.dart` (Session.fromJson round-trip, `AccessLevel.atLeast`), `test/shell/nav_filter_test.dart` (bartender default permissions → exactly the 5 ids; admin → all).
9. Report in `docs/phase-1/reports/WS-D.md`.

### WS-E — Admin screens: personas matrix, users, outlets, devices (frontend)

**Owns:** `frontend/lib/features/personas/**`, `frontend/lib/features/outlets/**`, `frontend/lib/features/devices/**`, `frontend/lib/features/users/**`, `frontend/test/admin/**`.

Use the WS-C kit (1.8) and WS-D session API (`can`, `Perm`, `AccessLevel`, `dioProvider` from `core/providers.dart`). Don't touch router/nav (WS-D registers your screens).

1. `features/personas/data/personas_repository.dart` (catalog, list, create/duplicate, patch, delete, get/put permissions) and models.
2. `features/personas/presentation/personas_screen.dart` → `PersonasScreen` matching the Permissions board: matrix table, rows grouped by permission group, one column per persona; each cell is a tappable chip showing level (Edit / View / Limited ≤ 10% / Request / Approve / None) that opens a small editor (level choice + limit field when the key has `limitUnit`); Admin column read-only with a lock; unsaved-changes bar "You changed N permissions. They apply to all X users the next time they sign in." with Cancel / Save; side panel for the selected persona (name, home screen, login method PASSWORD/PIN, Delete persona with the in-use rule message, Duplicate persona, New persona). Read-only when `admin.users` < EDIT. Wide matrix scrolls horizontally.
3. `features/users/…` update in place (keep class `UsersScreen`, file `users_screen.dart`): list with `AppDataTable` (name, username, outlets + persona chips, PIN set yes/no, status); edit panel with display name, email, phone, active, outlet assignments (rows of outlet + persona selects, one default radio), "Set PIN" dialog (4 digits twice, shows `PIN_TOO_SIMPLE`), reset password (existing endpoint). Move HTTP calls into `features/users/data/users_repository.dart`.
4. `features/outlets/presentation/outlets_screen.dart` → `OutletsScreen`: list + create/edit dialog (name, code, address, timezone default Asia/Kolkata, active).
5. `features/devices/presentation/devices_screen.dart` → `DevicesScreen`: list by outlet (name, type, last seen, status), "Register device" dialog → shows the returned device key once with a copy button and the warning "This key is shown once. Enter it on the tablet's PIN screen."; deactivate with confirm.
6. Every screen: `PageHeader`, loading/empty/error states from the kit, toasts on save, errors via `InlineAlert` using the API `code` → friendly message map.
7. Tests in `frontend/test/admin/`: personas matrix cell editor clamps limit input to numbers; read-only mode hides Save.
8. Report in `docs/phase-1/reports/WS-E.md`.

---

## 3. Integration (done by the planner after all workstreams report)

1. Cross-check names and shapes against this contract; resolve "Requests for other workstreams".
2. Grep for leftovers: imports of deleted `admin_shell.dart`, `role ==` checks in the frontend, `@Roles` on routes that now have `@Can`.
3. Static review of the migration SQL against the Prisma schema.
4. Update `docs/ROADMAP.md` Phase 1 status and write `docs/phase-1/INTEGRATION.md` with the manual test script:
   1. `npm install && npx prisma migrate dev && npm run seed && npm test` in `backend/`.
   2. `flutter pub get && flutter test && flutter run -d chrome` in `frontend/`.
   3. Admin login → sees all nav items → Personas matrix loads → change Bartender discount to 8% → Save.
   4. Devices → register a POS tablet → copy key → `/pin` → paste key → pick `bartender1` → wrong PIN twice (attempts left shown) → right PIN `2580` → shell shows exactly 5 nav items.
   5. Wrong PIN 3 times → locked for 5 minutes with countdown.
   6. Forgot password → reset link appears in backend log → reset → old refresh token rejected.

---

## 4. Addendum — rebased onto `main` @ 3f072bc (PR #1 merged 24 Nov)

The branch now lives in `/home/claude/enterprise` on top of current `main`. WS-A and WS-C are done and carried over. WS-B, WS-D and WS-E had partial work; it was carried over too, and **ten files have git conflict markers** (`<<<<<<< ours` = main, `>>>>>>> theirs` = the partial Phase 1 work). Resolve them by keeping main's features AND adding Phase 1. Files with conflicts:
`backend/src/app.module.ts`, `backend/src/modules/auth/auth.controller.ts`, `auth.module.ts`, `auth.service.ts`, `backend/src/modules/users/users.controller.ts`, `users.service.ts` (WS-B) · `frontend/lib/core/router/app_router.dart`, `frontend/lib/features/auth/data/auth_repository.dart` (WS-D). After resolving, run `git add <file>` on each so `git status` shows no `UU` entries. `schema.prisma` and `seed.ts` are already resolved.

What main added that Phase 1 must respect:

1. **Repository pattern (hard convention, see `.claude/skills/common-backend.md`).** Controllers call services; services call `<feature>.repository.ts`; only repositories touch Prisma. New Phase 1 modules (personas, outlets, devices, notifications) must follow it, and auth/users changes go through `auth.repository.ts` / `users.repository.ts`. Read the `.claude/skills/*.md` files for the modules you touch.
2. **New modules to keep working:** `branding`, `kiosk`, `localisation`, `login-method` (STATIC + GOOGLE OAuth via `oauth-login.service.ts`), `payment-config`, `product-images`, `common/storage/blob-storage`, and a reworked `invoice`. `UploadsModule` is still imported by `app.module.ts` and is now provided by WS-A's `backend/src/modules/uploads/`.
3. **User changes on main:** `email` and `passwordHash` are nullable (OAuth users have no password). Password login must reject users with no `passwordHash` as INVALID_CREDENTIALS. **OAuth login must return the same Phase 1 session payload (1.5)** — route it through the shared `buildSession` helper.
4. **Feature grants (`AppFeature`, `UserFeatureGrant`)**: main added per-user feature toggles. In Phase 1 **persona permissions are the source of truth** for access and navigation. Keep the feature-grant tables and endpoints compiling and working (marked deprecated, removal in Phase 2), and keep `features` in the login response's `user` object for backward compatibility. Map for nav: dashboard → `reports.view`, products → `menu.edit`, tax → `admin.settings`, users → `admin.users`, orders → `sales.orders.take`, appearance → `admin.themes`; main's admin-only screens localisation, settings, kioskAdmin, branding → `admin.settings` (VIEW to see, EDIT to change).
5. **KIOSK role**: main has `AppRole = 'ADMIN' | 'USER' | 'KIOSK'` and a kiosk display at `/kiosk`. Add a 9th system persona `kiosk / Kiosk display / PASSWORD / /kiosk` with every permission NONE and `isSystem = true` — WS-B may edit `backend/src/common/permissions/catalog.ts` and the Phase 1 migration SQL **only** to add this persona and map users whose role is `KIOSK` to it at MAIN. Legacy `role` in the session becomes `'KIOSK'` for that persona. Frontend: a kiosk session goes straight to `/kiosk` (full screen, no shell).
6. **Payment methods on main** include `CARD` and `PaymentMethodConfig` keyed by `storeId` (`'default'`). Leave as is in Phase 1; outlet-level payment config is Phase 2.
7. **Tenant scoping scope:** `TENANT_MODELS` stays as WS-A wrote it. Main's newer models (Invoice*, PaymentMethodConfig, PaymentGatewayProfile, BrandLogo, KioskConfig, FeaturedItem, ProductImage, Translation*) are **not** tenant-scoped in Phase 1 (single default tenant). Note this in reports as a Phase 1b follow-up.
8. **Frontend on main:** new screens `features/settings/settings_screen.dart`, `features/branding/branding_screen.dart`, `features/localisation/localisation_screen.dart`, `features/kiosk/kiosk_admin_screen.dart` and `kiosk_display_screen.dart`, `products/product_images_dialog.dart`, `core/features/app_feature.dart` + `feature_provider.dart`, and a reworked `admin_shell.dart` and `users_screen.dart`. WS-D mounts settings/branding/localisation/kiosk-admin in the new shell under **Settings** (routes `/settings/general`, `/settings/branding`, `/settings/localisation`, `/settings/kiosk`, permission `admin.settings` VIEW) and replaces `admin_shell.dart`. WS-E merges main's `users_screen.dart` features (read it) into the Phase 1 users screen instead of dropping them; feature-grant editing stays available there under an "Advanced (legacy)" section.
9. Frontend `AuthController`/`authControllerProvider` (main) is used by kiosk screens and others: WS-D either keeps a thin compatibility `authControllerProvider` that reads from the new `sessionProvider`, or updates every caller (grep for `authControllerProvider`) — no dangling imports.
