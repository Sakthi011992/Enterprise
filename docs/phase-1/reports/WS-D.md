# WS-D report: session, routing, shell, auth screens (frontend)

Status: written, not compiled or tested (no Flutter SDK or network here). Every WS-D file was reread for imports, constructor names and leftover conflict markers. A script confirmed each relative and `package:pos_billing/` import in the WS-D files resolves to a real file. `grep` finds no `<<<<<<<`, `=======` or `>>>>>>>` under `frontend/`. Nothing was committed.

## Files created, changed or removed

Resolved conflicts (staged with `git add`):
- `frontend/lib/core/router/app_router.dart`: kept Phase 1 routes and redirects. Added main's `/kiosk` route outside the shell and the legacy `/admin` redirects. Removed main's `_CashierShell` and the `AdminShell` route.
- `frontend/lib/features/auth/data/auth_repository.dart`: kept the Phase 1 `AuthRepository` (`_guard`, `_persist`, `AuthOutcome`). Main's feature-list `login` was dropped because nothing else called it.

Replaced or removed (section 4, items 8 and 9):
- `frontend/lib/features/admin/presentation/admin_shell.dart`: deleted. The new shell replaces it.
- `frontend/lib/features/auth/presentation/auth_controller.dart`: deleted. Every caller now uses `sessionProvider`. Callers updated: `kiosk_display_screen.dart` (logout), `app_router.dart`, `core/features/feature_provider.dart`. A grep finds no remaining `authControllerProvider`, `AuthController` or `admin_shell` references.

Changed:
- `frontend/lib/core/features/feature_provider.dart`: `userFeaturesProvider` and `featureProvider` now derive main's legacy `AppFeature` set from session permissions. Mapping: dashboard to `reports.view`, products to `menu.edit`, tax to `admin.settings`, users to `admin.users`, orders to `sales.orders.take`, appearance to `admin.themes`, and localisation, settings, kioskAdmin and branding to `admin.settings`. Each needs VIEW.
- `frontend/lib/core/shell/nav_registry.dart`: added four Settings items, all `admin.settings` VIEW: `/settings/general` (General settings), `/settings/branding`, `/settings/localisation`, `/settings/kiosk`. Added the `Guests & displays` group label to `navGroups`.
- `frontend/lib/features/kiosk/presentation/kiosk_display_screen.dart`: logout goes through `sessionProvider`.

Already in the tree from the earlier partial run, reviewed and kept as they are:
- `frontend/lib/core/auth/`: `api_error.dart`, `permission_keys.dart`, `permissions.dart` (`canOf`, `canProvider`, `can`), `session.dart`, `session_controller.dart`.
- `frontend/lib/core/shell/`: `app_shell.dart`, `command_palette.dart`, `nav_registry.dart`, `notifications.dart`, `notifications_panel.dart`, `pinned_nav.dart`, `placeholder_screen.dart`.
- `frontend/lib/features/auth/presentation/`: `auth_scaffold.dart`, `login_screen.dart`, `forgot_password_screen.dart`, `reset_password_screen.dart`, `outlet_picker_screen.dart`, `pin_login_screen.dart`.
- `frontend/lib/core/network/dio_client.dart`, `frontend/lib/core/storage/session_store.dart`, `frontend/lib/main.dart` (localisation delegates and `supportedLocales` from `package:flutter_gen/gen_l10n/app_localizations.dart`).
- Tests: `frontend/test/auth/session_test.dart`, `frontend/test/shell/nav_filter_test.dart`.

## Routes

- Public: `/login`, `/forgot-password`, `/reset-password?token=`, `/select-outlet`, `/pin`.
- Outside the shell: `/kiosk` (`KioskDisplayScreen`, full screen).
- Inside `AppShell`: `/dashboard`, `/pos`, `/orders`, `/menu`, `/stock-count` and `/my-shifts` (placeholders), `/users`, `/settings/general`, `/settings/personas`, `/settings/outlets`, `/settings/devices`, `/settings/tax`, `/settings/branding`, `/settings/localisation`, `/settings/kiosk`, `/settings/appearance`, `/settings/appearance/themes`, `/settings/appearance/themes/:id`, and `/dev/components` (debug only).
- Redirects: signed out goes to `/login`. Signed in on a sign-in path, or on a route the persona cannot see, goes to `persona.homeRoute`. Kiosk personas therefore land on `/kiosk`. Legacy `/admin/*` and `/billing` redirect to their new paths.

## Done against the plan

- Session layer per 1.8: `Session`, `PermissionGrant`, `AccessLevel.atLeast`, `Perm`, `SessionController` with every method in 1.8, `can` and `canProvider`, and `SessionStore` additions.
- `AuthRepository` covers every 1.5 endpoint and parses errors into `ApiError`.
- `DioClient`: refresh flow kept. A failed refresh clears the session and bumps `sessionExpiredSignal`, which the controller listens to. `X-Device-Key` is sent on `/auth/pin/*`.
- Login, forgot-password, reset-password, outlet picker and PIN login screens, with the error codes from 1.5 mapped to the copy in section 2 of the plan. PIN login shows attempts left and a lockout countdown.
- Shell: top bar (outlet switcher, language menu with Tamil and Hindi disabled, theme toggle, notifications with a 60 s poll, account menu), Ctrl/Cmd+K command palette, grouped side nav filtered by permission, pinning up to 5 items (persisted), responsive breakpoints at 1280 and 768 px, and `DensityScope` (`pos` on `/pos`).
- Nav registry lists every item in 1.8 and section 4. A Bartender session sees exactly the five exit-test items. Admin sees all items.
- Main's settings, branding, localisation and kiosk-admin screens are mounted under Settings. WS-E's `PersonasScreen`, `OutletsScreen`, `DevicesScreen` and `UsersScreen` are mounted at their routes.
- WS-C request met: `localizationsDelegates` and `supportedLocales` in `main.dart`. `ComponentGalleryScreen` mounted at `/dev/components` under `kDebugMode`.

## Stubbed or simplified

- Approve and Decline in the notifications panel are disabled with the tooltip "Approvals arrive in Phase 2".
- Language menu: only English is active.
- Stock count and My shifts are placeholders.
- The outlet picker only appears for a password login that needs an outlet choice. Switching outlets happens from the top bar, which calls `switchOutlet`.
- Main's settings, branding, localisation and kiosk screens keep their own `Scaffold` and `AppBar`, so they show a second app bar inside the shell. Restyling them is out of scope here.

## Requests for other workstreams

- WS-B (backend): the `kiosk` persona must have `homeRoute: "/kiosk"` and map legacy `KIOSK` users to it, as section 4 item 5 says. The frontend depends on that `homeRoute`.
- WS-E: `UsersScreen` is still main's version, which uses `AppFeature` grants. WS-E's rewrite should keep the "Advanced (legacy)" feature section from section 4 item 8. `personas_screen.dart` and `outlets_screen.dart` call `can(...)`. Their `permissions.dart` import is needed, and it is present in the tree now.

## Open risks

1. Nothing has been compiled. Expect a few analyzer infos on first build. `DropdownButtonFormField` and `WidgetState` versions are the same as WS-C's notes.
2. `branding_screen.dart` (main) imports `dart:html`. Main already had this import in `admin_shell.dart`, and the router now imports it unconditionally, so non-web builds will fail as they would have before. This is not new in WS-D.
3. `PinPad` hardware keyboard and the command palette's arrow-key handling are untested. The palette's `Focus` only receives keys when no text field consumes them first.
4. `pin_login_screen` calls `_startTicker()` from `build` when the account is locked. This works but is not ideal. Moving it into a `ref.listen` callback would be cleaner.
5. `session_controller.dart` restores a stored session in its constructor without checking the token against the server. Stale sessions are caught by `refreshMe` or the first 401.

## Memory

Nothing from the memory store was used or needed for this task.
