# Phase 1 — integration notes and test script

Built from `docs/phase-1/PLAN.md` (sections 1–4). Workstream reports are in `docs/phase-1/reports/`.

**Nothing in this branch has been compiled or run yet.** It was written in a sandbox with no network, so `npm install`, `prisma`, `flutter pub get`, the Jest specs and the Flutter tests have not been run. Expect a round of compile fixes on first build.

## What the integrator changed on top of the workstreams

- Rebased all work onto `main` @ 3f072bc (PR #1) and resolved the merge conflicts in `schema.prisma` and `seed.ts` (kept main's OAuth, feature grants, kiosk, locale and invoice changes; added Phase 1).
- Renamed the Phase 1 enum `LoginMethod` → `PersonaLoginMethod` in the schema and migration. Main already has `enum LoginMethod { STATIC GOOGLE }`.
- `RolesGuard` now skips the legacy `@Roles` check when a route declares `@Can`; `PermissionGuard` has already enforced the persona permission. Without this a Manager with `menu.edit EDIT` was still refused on admin-only routes.
- `GET /outlets` returns every tenant outlet to callers with `admin.users` VIEW too (needed to assign staff to outlets).
- `POST /users`: `email` is optional (PIN-only staff).

## Run it locally

```bash
# backend
cd backend
npm install
npx prisma migrate dev        # applies 20261125100000_phase1_foundation
npm run seed
npm test
npm run start:dev

# frontend
cd ../frontend
flutter pub get               # if intl conflicts with flutter_localizations, align intl to the SDK pin
flutter test
flutter run -d chrome
```

## Manual test script

1. Sign in as `admin` / `Admin@123`. You land on `/dashboard` and see every nav item, including Settings → Personas & permissions, Outlets, Devices, General, Branding, Localisation, Kiosk.
2. Personas & permissions: the matrix loads; Admin column is locked. Change Bartender "Give discount" to Limited 8% → Save → "You changed 1 permission…" bar clears.
3. Devices → Register device (Main outlet, POS tablet) → copy the key (shown once).
4. Open `/pin` → paste the device key → tiles show `bartender1` → enter a wrong PIN twice ("2 tries left", "1 try left") → enter `2580` → the shell shows exactly **5** nav items: POS billing, Orders, Menu & products, Stock count, My shifts.
5. Sign out → `/pin` → wrong PIN 3 times → "Locked" with a 5-minute countdown.
6. Forgot password → enter `admin` → the reset link appears in the backend log → open it → set a new password → the old refresh token is rejected.
7. Users → edit `bartender1` → outlets/persona chips, Set PIN (`1234` is rejected as too simple), legacy feature grants still under "Advanced (legacy)".
8. A user with role KIOSK signs in → goes straight to `/kiosk` with no shell.
9. Google sign-in (if enabled in login methods) returns the same session shape and lands on the persona's home route.

## Known gaps (follow-ups)

- **Tenant scoping** covers Outlet, Persona, User, Product, GlobalTaxSetting, Order, ProductImportLog, AuditLog, Device, Notification. Main's newer models (Invoice*, PaymentMethodConfig, PaymentGatewayProfile, BrandLogo, KioskConfig, FeaturedItem, ProductImage, Translation*) are still single-tenant → Phase 1b. Nested `include`/`connect` writes are not scoped.
- Writes outside a request (no tenant in context) on tenant models fail on NOT NULL `tenantId` by design.
- `@Roles` still gates routes without `@Can`.
- Feature grants (`UserFeatureGrant`) are kept but deprecated; navigation and access use persona permissions.
- OAuth-created users have no outlet until an admin assigns one (login returns `NO_OUTLET_ACCESS`).
- Main's STATIC login-method gate in `auth.controller.ts` swallows its own error (`.catch(() => {})`), so disabling STATIC doesn't block password login. Pre-existing; not changed.
- `features/branding/branding_screen.dart` (from main) imports `dart:html`, which breaks Android/iOS builds; now reachable from the router. Pre-existing; needs a conditional import.
- Existing orders keep `outletId = NULL`.
- Real translations for Tamil and Hindi are placeholders (English text, marked untranslated).
