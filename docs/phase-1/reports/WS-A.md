# WS-A report: data model, migration, tenancy, uploads (backend)

Status: complete as written, not compiled or run (no network). Nothing committed.

## Files

Changed:
- `backend/.gitignore`: `uploads/` changed to `/uploads/` (only the backend-root runtime folder is ignored). Root `.gitignore` already had `backend/uploads/`, unchanged.
- `backend/prisma/schema.prisma`: enums `AccessLevel`, `LoginMethod`, `DeviceType`; models `Tenant`, `Outlet`, `Persona`, `Permission`, `PersonaPermission`, `UserOutlet`, `StaffPin`, `Device`, `Notification`, `PasswordResetToken`. `User` gains `tenantId`, `displayName`, `phone`, and the relations; `roleId`/`Role` kept. `tenantId` plus index added to `Product`, `GlobalTaxSetting`, `Order`, `ProductImportLog`, `AuditLog`. `Order.outletId` (nullable, indexed).
- `backend/prisma/seed.ts`: rewritten, idempotent (see below).
- `backend/src/prisma/prisma.service.ts`: same class name and path. Now a class plus an interface merge, so it works as a DI token and carries the PrismaClient API. `createTenantPrismaClient()` returns `new PrismaClient().$extends(tenantScope)`.
- `backend/src/prisma/prisma.module.ts`: factory provider for `PrismaService`, plus `PrismaLifecycle` (`$connect` on init, `$disconnect` on destroy).

Created:
- `backend/prisma/migrations/20261125100000_phase1_foundation/migration.sql`: hand-written, see below.
- `backend/src/common/permissions/catalog.ts`: `ACCESS_LEVELS`, `AccessLevel`, `levelAtLeast`, `PERMISSION_CATALOG`, `PermissionKey`, `DEFAULT_PERSONAS` (with `matrix`), `LimitUnit`, `LoginMethodName`, `PersonaGrant`, `PermissionDefinition`, `DefaultPersona`.
- `backend/src/common/tenancy/tenant-context.ts`: `TenantContext` (`get`, `set`, `run`, `runAsSystem`), `TenantStore`.
- `backend/src/common/tenancy/tenant-context.middleware.ts`: `TenantContextMiddleware`.
- `backend/src/common/tenancy/tenant-scope.extension.ts`: `TENANT_MODELS`, `isTenantModel`, `scopeOperation` (pure, testable), `tenantScope` (Prisma extension).
- `backend/src/common/tenancy/tenant-scope.extension.spec.ts`: 10 tests (named per WS-A step 7; section 1.4 says `tenant-scope.spec.ts`).
- `backend/src/modules/uploads/storage.interface.ts`, `local-storage.service.ts`, `uploads.module.ts`. The uploads module was not in git history, so it was recreated from the spec. Products already imports it.
- `docs/phase-1/reports/WS-A.md` (this file).

## Done

- **Migration** (`20261125100000_phase1_foundation`): creates the enums and new tables with Prisma-style names. Inserts the default tenant (`Default venue`, slug `default`), the `MAIN` outlet, the 15 catalog permissions, the 8 personas (admin flagged `isSystem`), and the matrix as 67 non-NONE `persona_permissions` rows. Backfills `tenantId` on existing rows, sets NOT NULL, then adds indexes and FKs. Maps existing users: ADMIN role to `admin`, USER role to `cashier`, both at MAIN with `isDefault`.
- **Catalog and seed match**: `catalog.ts` mirrors PLAN 1.1 and 1.2 (checked row by row, including limits and home routes). The migration and seed both store only non-NONE grants; a missing row means NONE.
- **Seed**: upserts roles, catalog, tenant, MAIN outlet, personas, and matrix rows. Matrix rows are only created when missing, so admin edits survive a re-run. Admin user gets the admin persona at MAIN. Demo `bartender1` (password `Bartender@123`, PIN `2580`) gets the bartender persona at MAIN. Sample products and global tax get `tenantId`.
- **Tenancy**: `TenantContext` on AsyncLocalStorage. `scopeOperation` rules:
  - Reads, counts, aggregates, groupBy, updateMany, deleteMany: `where.tenantId` added.
  - findUnique, findUniqueOrThrow, update, delete, upsert `where`: `tenantId` added as an extra filter. This uses Prisma 5 extended where-unique (5.22 locked), so a row in another tenant is reported as not found. No post-check.
  - create, createMany, upsert create: `tenantId` set when missing. An explicit other-tenant `tenantId` throws.
  - update, updateMany, upsert update: moving a row to another tenant throws.
  - No tenant in context, `system: true`, or model outside `TENANT_MODELS`: pass-through.
- **Uploads**: `LocalStorageService` writes under `UPLOAD_DIR`, returns `${PUBLIC_BASE_URL}/uploads/<folder>/<uuid><ext>`. The folder and extension are sanitised. `remove` refuses paths outside the upload root and ignores ENOENT.

## Stubbed / deviations from the plan

- `Tenant` gained back-relation lists (`products`, `globalTaxSettings`, `orders`, `productImportLogs`, `auditLogs`, `devices`, `notifications`). `Device`, `Notification`, and `Order` got a `tenant` relation so their tenantId columns have FKs (the migration adds them). `Order.outlet` is a real FK (`ON DELETE SET NULL`).
- Prisma's create types require `tenantId`, which would break existing call sites (products, orders, users, tax, import, themes). To keep them compiling unchanged, `PrismaService` types create/createMany/upsert on the ten tenant models loosely (`(args: any) => any`). Read and update types stay strict. This is a compile-time relaxation only; the runtime scope still applies.
- Existing orders keep `outletId = NULL` (plan says nullable; no backfill). Tell me if you want them backfilled to MAIN.
- Matrix stored as non-NONE rows only (67 rows), not all 120 combinations.
- PIN hashes are bcrypt (seed uses `bcrypt.hash(pin, 10)`). The plan does not name the algorithm; WS-B's `pinLogin` must use `bcrypt.compare`.

## Known risks

1. **Writes without a tenant context fail.** Any create outside a request (background job, public route that writes, import without JWT context) will hit NOT NULL on `tenantId` unless the caller runs under `TenantContext.run({ tenantId })`. Check `product-import.service.ts` (`importFromBuffer` runs inside a request, so it should be fine).
2. **Relation traversal is not scoped.** `include`/nested reads and nested `connect` do not get a tenant filter. Rows reached only through a scoped parent are safe, but a direct `include` of another model is not.
3. **Interactive transactions**: the extension is applied to `tx` (Prisma 5), but `tx` typing still requires `tenantId` for creates inside `$transaction(async tx => ...)`. No such creates exist today.
4. **Migration not run.** The SQL was written by hand and reviewed, not executed. The matrix insert uses VALUES casts (`::"AccessLevel"`, `::DECIMAL(12,2)`). Run `prisma migrate dev` and check for drift before merging.
5. **Spec needs a generated client**: `tenant-scope.extension.spec.ts` imports `@prisma/client` (for `Prisma.defineExtension`), so `prisma generate` must have run before `npm test`.

## Requests for other workstreams

- **WS-B (`app.module.ts`)**: apply `TenantContextMiddleware` to all routes in `configure(consumer)`. Register `UploadsModule` as already imported (path unchanged).
- **WS-B (`JwtStrategy.validate`)**: call `TenantContext.set({ tenantId, outletId, userId })` after loading the user. Device lookup for `X-Device-Key` should use `TenantContext.runAsSystem(() => prisma.device.findFirst({ where: { keyHash, isActive: true } }))`, then set the store from the device's `tenantId`/`outletId`.
- **WS-B (`pinLogin`)**: verify PINs with `bcrypt.compare(pin, staffPin.pinHash)`.
- **WS-B (`PermissionsService`)**: `levelAtLeast` and `ACCESS_LEVELS` are exported from `backend/src/common/permissions/catalog.ts`.
- **WS-B (`.env.example`)**: `UPLOAD_DIR` and `PUBLIC_BASE_URL` are already there; no change needed for WS-A.

## Memory

No memory was used for this task.
