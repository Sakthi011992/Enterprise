---
name: products
description: Work on the Enterprise POS backend's products module — CRUD, activate/deactivate, image upload, Excel bulk import, search/filter. Use whenever the user asks to add/modify product endpoints, the Excel import pipeline, product image handling, or anything under backend/src/products.
---

# Products Module (Enterprise POS backend)

NestJS feature module for catalog management.

## Module layout

```
src/products/
├── dto/                   # CreateProductDto, UpdateProductDto, ImportSummaryDto
├── entities/               # ProductEntity
├── products.controller.ts
├── products.service.ts
├── products.repository.ts  # Prisma access
└── products.module.ts
```

## Endpoints (base `/api/v1`)

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/products` | auth | search, `?isActive=`, paginated |
| GET | `/products/:id` | auth | |
| POST | `/products` | ADMIN | `{ name, description?, price, taxPercentage? }` |
| PATCH | `/products/:id` | ADMIN | partial update |
| PATCH | `/products/:id/status` | ADMIN | `{ isActive }` |
| DELETE | `/products/:id` | ADMIN | soft delete |
| POST | `/products/:id/image` | ADMIN | multipart `file` |
| POST | `/products/import` | ADMIN | multipart `.xlsx` → import summary |
| GET | `/products/import/template` | ADMIN | downloadable template |

## Excel import pipeline (docs/ROADMAP.md Phase 2 — implement to this contract)

1. Accept a multipart `.xlsx` upload.
2. Validate each row (required fields, numeric price/tax, no negative values).
3. Produce a row-level error report for invalid rows — don't abort the whole import on one bad row.
4. Bulk-insert valid rows.
5. Skip duplicates (match on product name, or SKU if the schema has one) rather than erroring.
6. Return an import summary: counts of inserted / skipped / failed rows, plus the error report.
7. `GET /products/import/template` returns a blank `.xlsx` with the expected column headers — keep it in sync with the validation rules.

## Image upload

- Goes through the shared `uploads` module's `StorageService` abstraction (see the `uploads` skill) — never write files directly to disk from this module or bypass the storage interface, since that breaks the local→S3 swap path.

## Tax on products

- `taxPercentage` on a product is a nullable override. `null` means "use the global tax setting." Resolution logic itself lives in the `tax` module (`resolveTaxPercentage`) — don't duplicate that logic here.

## Conventions to preserve

- `DELETE /products/:id` is a soft delete; deactivated/deleted products should not appear in default list results or be orderable, but must remain queryable for historical order/invoice display (orders snapshot the product name/price/tax at order time — never resolve those live from a possibly-deleted product).
- `PATCH /products/:id/status` is a dedicated endpoint for activate/deactivate — don't fold this into the generic `PATCH /products/:id` update.
- List endpoint follows the shared pagination contract: `?page=1&limit=20&search=<q>` → `{ data, meta: { page, limit, total, totalPages } }`.
