# WS-E report: admin screens (personas, users, outlets, devices)

Status: code written and reviewed by reading. Nothing compiled or run (no Flutter SDK here). Not committed.

## Files

Created:
- `frontend/lib/features/users/presentation/user_edit_panel.dart`: side panel for one user. Details, outlet access rows with one default, Set PIN, Reset password, Advanced (legacy) section at the bottom.
- `frontend/lib/features/users/presentation/user_create_dialog.dart`: new-user dialog. Creates the account, then assigns one outlet and persona. Keeps the new id so a failed assignment does not create a second user.
- `frontend/lib/features/users/presentation/user_legacy_features.dart`: "Advanced (legacy)" feature-grant section (main's `AppFeature` checkboxes, same wire format).
- `frontend/test/admin/persona_matrix_test.dart`: `sanitizeLimitInput`; cell editor clamps the limit field to digits and 100%; read-only matrix does not open the editor; read-only changes bar hides Save.
- `frontend/test/admin/admin_models_test.dart`: persona/user/device model parsing, limit-only-with-LIMITED, `AdminApiError.friendly`, `listFrom`.
- `docs/phase-1/reports/WS-E.md` (this file).

Rewritten:
- `frontend/lib/features/users/presentation/users_screen.dart`: `UsersScreen` (same class name). `AppDataTable` with local search, outlet/persona chips, PIN and status badges, "New user", selection opens the side panel. Read-only without admin.users EDIT.

Changed (partial work from the stopped run):
- `features/users/data/users_repository.dart`: `list()` has no server search. Added `features(id)` / `setFeatures(id, set)` for legacy grants and `userFeaturesProvider`. `usersListProvider` is no longer a family.
- `features/personas/presentation/personas_screen.dart`, `features/outlets/presentation/outlets_screen.dart`, `features/devices/presentation/devices_screen.dart`: these called `can(...)` without importing `core/auth/permissions.dart` (compile error). Added that import, removed the unused `session_controller.dart` import.
- `features/personas/presentation/permission_cell_editor.dart`, `features/users/presentation/user_secret_dialog.dart`: added explicit `package:flutter/services.dart` import for `TextInputType`.

Reviewed and left as they were: `features/personas/**` (repository, models, matrix, side panel, changes bar, name dialog, cell editor), `features/outlets/**`, `features/devices/**` (repository, screen, register dialog), `features/users/presentation/user_secret_dialog.dart` (apart from the import).

## What is done (against PLAN 2, WS-E, and section 4 item 8)

- Personas: matrix grouped by catalog group, one column per persona, cell editor with level and limit (limit only for keys with `limitUnit`, clamped to 100 for percent), Admin column locked, unsaved-changes bar with count and affected users, side panel (name, description, home screen, sign-in method, duplicate, delete with in-use rule). Read-only without admin.users EDIT. Wide matrix scrolls both ways.
- Users: list, search, outlets and personas, PIN yes/no, status. Panel: display name, email, phone, active, outlet rows (one default), Set PIN (`showSetPinDialog`, 4 digits twice, `PIN_TOO_SIMPLE` shown), Reset password, legacy grants under "Advanced (legacy)".
- Users merged with main's `users_screen.dart`: create user (with persona picker), activate/deactivate (now the Active switch in the panel), reset password, manage features (moved into "Advanced (legacy)"). Main's `limit: 100` kept.
- Outlets: list, new/edit dialog (name, code 2-10 characters, address, timezone default Asia/Kolkata, active on edit).
- Devices: outlet select, device table (name, type, last seen, status), register dialog that shows the key once with a copy button and the "shown once" warning, deactivate with confirm.
- Every screen uses `PageHeader`, the kit's loading/empty/error states, toasts on save, and `InlineAlert` with `AdminApiError.friendly` for API codes.
- Route names match what `core/router/app_router.dart` already imports: `UsersScreen` on `/users`, `PersonasScreen` on `/settings/personas`, `OutletsScreen` on `/settings/outlets`, `DevicesScreen` on `/settings/devices`.

## Stubbed or changed from the plan

- Users: the theme toggle that main's users screen had in its app bar is gone. The shell owns that now.
- Users create: `roleName` is sent because the backend DTO requires it. It is derived from the chosen persona (`admin` gives `ADMIN`, anything else `USER`).
- Users edit: email is optional here (blank means unchanged; the API cannot clear it from this screen). Create requires email, as the DTO does.
- Feature grants: only the six `userGrantable` features. Admin-only `AppFeature` values are not shown, as on main.

## Known risks

- Nothing compiled. Checked by reading: every local import resolves, no conflict markers left under `frontend/lib` or `frontend/test`, and every kit/session name used exists with the signature used (`AppSelectItem` positional, `StatusTone.info`, `t.color.border.standard`, `t.spacing.xs/sm/md`, `t.borderWidth.none/hairline/thick`, `t.radius.pill/md`).
- `AppSelect` wraps `DropdownButtonFormField`, which asserts when `value` is not among `items`. The outlet and persona selects always include the current value (the user panel adds the assignment's own name when the list does not have it; the create dialog picks from loaded items).
- Outlet choices in the user panel come from `GET /outlets`. That endpoint returns only the caller's own outlets unless the caller has admin.settings VIEW. An admin with admin.users but not admin.settings would only see their own outlets when assigning another user.
- `Device.fromJson` needs `outletId` on each device, `isActive`, `lastSeenAt` (optional).
- Widget tests have not run. The `PersonaMatrix` tap test relies on `find.text('Edit')` matching one cell.

## Requests for other workstreams

WS-B (backend):
1. `GET /outlets` should return all tenant outlets to a caller with admin.users VIEW as well as admin.settings VIEW. Otherwise the user-assignment select is limited to the admin's own outlets.
2. `GET /devices` rows must include `outletId`; the client parses it as required.
3. `POST /users`: the DTO requires `email` and `roleName`. The client always sends both. If Phase 1 keeps `email` nullable, make it optional in the DTO.
4. `PATCH /users/:id`: `displayName` and `phone` may be `null` to clear. `email` is only sent when non-empty.
5. `GET /users/:id/features` returns wire names (`"DASHBOARD"`, ...); `PUT` takes `{ features: [...] }`. The client relies on both.

WS-D (frontend, session/shell):
1. `features/admin/presentation/admin_shell.dart` still imports `UsersScreen` and uses `const UsersScreen()`. The constructor still matches. Deleting the file, as the plan says, resolves the import.
2. This workstream imports `core/auth/permissions.dart` (`can`), `core/auth/permission_keys.dart` (`Perm`), and `core/auth/session.dart` (`AccessLevel`). Please keep those names and exports.

WS-C (kit): none. The users screen passes `selected` to `AppDataTable` without `onSelectionChanged`. The table then highlights the selected row and shows no checkboxes, which is what the code does now (`selectable = onSelectionChanged != null`). If WS-C changes that, the users screen will show checkboxes.

## Memory

No stored memory was used for this task.
