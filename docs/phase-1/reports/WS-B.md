# WS-B report: auth, permissions, admin APIs (backend)

Status: code complete per PLAN 1.5 to 1.7, section 2 WS-B and section 4 items 1 to 5 and 9. Not compiled or run (no network, no `node_modules`). Not committed. The six conflicted files are resolved and staged.

## Files

Changed (conflicts resolved, then `git add`):
- `backend/src/app.module.ts`: main's modules plus Phase 1 (`PermissionsModule`, `PersonasModule`, `OutletsModule`, `DevicesModule`, `NotificationsModule`). Guards in order JwtAuthGuard, PermissionGuard, RolesGuard. `TenantContextMiddleware` on all routes.
- `backend/src/modules/auth/auth.controller.ts`: main's STATIC gate kept, plus the Phase 1 routes.
- `backend/src/modules/auth/auth.module.ts`: imports `LoginMethodModule` through `forwardRef`.
- `backend/src/modules/auth/auth.service.ts`: rewritten on `AuthRepository`. Password login, `completeLogin`, select/switch outlet, refresh, logout, me, `buildSession`, forgot/reset password, PIN staff/login.
- `backend/src/modules/users/users.controller.ts`, `users.service.ts`: main's feature-grant endpoints kept (deprecated), Phase 1 `@Can` plus outlets, PIN, displayName/phone.

Created:
- `backend/src/modules/auth/auth.repository.ts`, `legacy-role.ts`
- `backend/src/modules/personas/personas.repository.ts`
- `backend/src/modules/outlets/outlets.repository.ts`
- `backend/src/modules/devices/devices.repository.ts`
- `backend/src/modules/notifications/notifications.repository.ts`
- `backend/src/modules/users/users.repository.ts` (rewritten; main's feature grants included)
- `backend/src/modules/login-method/oauth.repository.ts`, `login-method.repository.ts`

Rewritten to the repository pattern (controllers to services to repositories):
- `modules/personas/`: `personas.service.ts`, `permissions.service.ts`, `permissions.module.ts` (global, provides `PersonasRepository`), `permissions-catalog.controller.ts`
- `modules/outlets/outlets.service.ts`, `outlets.module.ts`
- `modules/devices/devices.service.ts`, `devices.module.ts`
- `modules/notifications/notifications.service.ts`, `notifications.module.ts`
- `modules/auth/device-auth.service.ts`, `jwt.strategy.ts`
- `modules/login-method/login-method.service.ts`, `login-method.module.ts`, `oauth-login.service.ts` (OAuth now returns the shared session through `AuthService.completeLogin`)

Edited:
- `backend/src/common/permissions/catalog.ts`: 9th default persona `kiosk` (`Kiosk display`, `/kiosk`, PASSWORD, isSystem, empty matrix). Allowed by section 4 item 5.
- `backend/prisma/migrations/20261125100000_phase1_foundation/migration.sql`: kiosk persona inserted. Users with role `KIOSK` map to `kiosk` at MAIN (were mapped to cashier). Allowed by section 4 item 5.
- `backend/src/common/decorators/current-user.decorator.ts`: `AuthUser.role` includes `'KIOSK'`.
- `backend/src/modules/personas/personas.service.ts`, `personas.repository.ts`, `personas.service.spec.ts`
- `backend/src/modules/users/dto/user.dto.ts`: `roleName` optional (default USER), accepts `KIOSK`.
- `backend/src/modules/auth/auth.service.pin.spec.ts`, `auth.service.reset.spec.ts`: constructors and mocks updated for the repository layer.
- `backend/src/modules/auth/password-reset.notifier.ts`: `email` nullable (`User.email` is nullable).
- `backend/src/modules/login-method/login-method.module.ts`: `forwardRef` to `AuthModule`.
- `docs/API.md`: Session payload, Auth, Permissions and personas, Outlets, Devices, Notifications, Users, error codes.

Already correct from earlier work, checked and left alone: `.env.example` (`APP_BASE_URL` present), `common/filters/*`, `common/guards/permission.guard.ts` and spec, `common/decorators/can.decorator.ts`, `auth/token.util.ts`, `auth/dto/auth.dto.ts`, `auth/password-reset.notifier.ts` (apart from the email type), and `@Can` on products, tax, orders, payments, reports and themes (matches PLAN 1.6).

## Done

- **Session payload** (`AuthService.buildSession`): every login path uses it, including OAuth. Carries `user` (with `features` for main's compatibility), `tenant`, `outlet`, `persona`, `permissions` (every catalog key), `outlets`, legacy `role` (`ADMIN` / `KIOSK` / `USER`).
- **Password login**: rejects users with no `passwordHash` as INVALID_CREDENTIALS. Returns `needsOutlet` plus a 5-minute selection token when the user has several outlets and no single default.
- **Permissions**: `PermissionsService` (30 s cache per persona, `check`, `assertWithinLimit`, `invalidate`, `catalog`). `PermissionGuard` and `@Can` as in 1.6.
- **Admin APIs** (1.7): catalog, personas CRUD, persona matrix GET/PUT (rejects unknown keys, limit on a non-limit key, and grants above the caller's own level), outlets, devices (key shown once, sha256 stored), notifications, user PIN, user outlets.
- **PIN login**: bcrypt PIN hash (matches WS-A seed). 3 wrong PINs lock for 5 minutes (423 PIN_LOCKED). `attemptsLeft` reported. Success resets. Expired lock starts a fresh cycle.
- **Password reset**: 32 random bytes, sha256 stored, 30-minute expiry, older tokens invalidated. Reset claims the token atomically and bumps `tokenVersion`. Link is logged by `LoggerPasswordResetNotifier`.
- **Tenancy**: `JwtStrategy` and `DeviceAuthService` set `TenantContext`. Device lookup runs under `runAsSystem` inside the repository.
- **Tests** (Jest, mocked Prisma through the real repositories): `permission.guard.spec.ts`, `auth.service.pin.spec.ts`, `auth.service.reset.spec.ts`, `personas.service.spec.ts`. Not run.

## Stubbed / deviations

- **Login-method gate kept as main wrote it.** `login` calls `loginMethods.assertEnabled(STATIC).catch(() => {})`. The `.catch` swallows the error, so disabling STATIC has no effect. I kept it unchanged. Decide whether to remove the `.catch` (and handle the no-config-row case) in a later change.
- **OAuth new users** are created in the default tenant with role USER and no outlet. They get 403 NO_OUTLET_ACCESS until an admin assigns one.
- **Legacy role changes** through `PATCH /users/:id` (`roleName`) update the legacy `roleId` only. Access comes from `userOutlets` and personas, so changing `roleName` does not change access. Persona assignment is through `PUT /users/:id/outlets`.
- **Feature grants** kept (`/users/:id/features`, `user.features`) and marked deprecated for Phase 2.
- **`@Roles` still on the existing routes** (products, tax, orders, payments, reports, themes, users) per PLAN 1.6. A Manager or Captain with the right `@Can` is still refused by `RolesGuard` on those routes until Phase 2 removes `@Roles`.
- **PIN for a user with no StaffPin** returns PIN_INVALID without attempts info. Matches the plan's "wrong PIN" path but reveals nothing extra.
- **Persona grant copy** (`POST /personas` with `copyFromId`) enforces the same no-escalation rule as PUT.
- Login-method service (main) moved to `LoginMethodRepository`. Its behaviour is unchanged.

## Known risks

1. **BLOCKER (WS-A): `LoginMethod` enum name clash.** `schema.prisma` declares `enum LoginMethod { PASSWORD PIN }` (around line 42) and `enum LoginMethod { STATIC GOOGLE }` (around line 675, main's). Prisma will reject the schema. The migration has the same clash: `20261125100000_phase1_foundation` runs `CREATE TYPE "LoginMethod" AS ENUM ('PASSWORD', 'PIN')`, but `20260829142232_add_enterprise_features` already creates `"LoginMethod"` as `('STATIC', 'GOOGLE')`, so a fresh migrate fails. Suggested fix: rename the Phase 1 enum to `PersonaLoginMethod` in `schema.prisma` (`Persona.loginMethod`) and in the migration (lines 9, 49, 192). No WS-B code imports that enum; it uses the string literals `'PASSWORD' | 'PIN'`, so the rename does not touch WS-B code.
2. **`schema.prisma` and `seed.ts` still show `UU`** in the git index. Their content is resolved per section 4, but they have not been `git add`-ed. This is WS-A's file, so I did not stage them.
3. **Migration persona count is now 9** (was 8) with `kiosk`. WS-A's report says 8. Seed upserts from `DEFAULT_PERSONAS`, so it picks up `kiosk` automatically.
4. **Not compiled.** No `node_modules`. A `tsc` pass with a stripped config found no syntax errors. The remaining errors were missing-module noise (`@nestjs/*`, `@prisma/client`, jest globals, `PartialType`). Type-level mistakes are still possible. Run `npm run build` and `npm test` first.
5. **Circular module import** `AuthModule` to `LoginMethodModule`, resolved with `forwardRef` on both sides. Watch for "Nest can't resolve dependencies" on boot.

## Requests for other workstreams

- **WS-A**: fix the `LoginMethod` clash (risk 1), then `git add` `schema.prisma` and `seed.ts`.
- **WS-A (confirm)**: the 8th persona count in your report is now 9.
- **WS-D (frontend)**:
  - Session `user.features` remains for compatibility. Use `role` (`'ADMIN' | 'USER' | 'KIOSK'`) only as a hint. Routing uses `persona.homeRoute`. A kiosk session lands on `/kiosk` (`persona.homeRoute`), full screen, no shell.
  - Login may return `{ needsOutlet: true, selectionToken, outlets }`. Show the outlet picker and call `/auth/select-outlet`.
  - PIN login returns 423 `PIN_LOCKED` with `details.lockedUntil`, and 401 `PIN_INVALID` with `details.attemptsLeft`.
  - `/auth/login-methods/google/token` returns the same session as password login.
- **WS-E (admin screens)**: `GET /users` rows include `displayName`, `phone`, `outlets`, `hasPin`, plus main's `role` and `featureGrants`. `roleName` accepts `ADMIN`, `USER`, `KIOSK`. Feature-grant endpoints are deprecated (keep under "Advanced (legacy)").
- **Main's kiosk module**: `KioskService.createDefault` upserts a `KioskConfig` for a user but does not create the user or assign an outlet. Kiosk accounts must be created through `POST /users` with `roleName: 'KIOSK'` (which assigns the kiosk persona at the first active outlet), or they cannot sign in (NO_OUTLET_ACCESS).
- **Phase 2**: remove `@Roles` from routes that now have `@Can`. Remove feature grants. Make role changes move persona assignments.

## Memory

No memory was used for this task.
