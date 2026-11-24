---
name: users
description: Work on the Enterprise POS backend's users module (admin CRUD over users, role assignment, password reset). Use whenever the user asks to add/modify user management endpoints, role-based access for users, or anything under backend/src/users.
---

# Users Module (Enterprise POS backend)

NestJS feature module for ADMIN-only management of user accounts (Admin / Cashier roles).

## Module layout

```
src/users/
├── dto/                # CreateUserDto, UpdateUserDto, ResetPasswordDto
├── entities/            # UserEntity (never expose passwordHash)
├── users.controller.ts
├── users.service.ts
├── users.repository.ts  # Prisma access — Repository Pattern
└── users.module.ts
```

## Endpoints (base `/api/v1`, ADMIN role required on all)

| Method | Path | Body |
|---|---|---|
| GET | `/users` | list, paginated, `?search=` |
| POST | `/users` | `{ username, email, password, roleName }` |
| GET | `/users/:id` | — |
| PATCH | `/users/:id` | `{ email?, isActive?, roleName? }` |
| PATCH | `/users/:id/reset-password` | `{ newPassword }` |
| DELETE | `/users/:id` | soft delete |

List endpoints follow the shared pagination contract:
`?page=1&limit=20&search=<q>` → `{ data: [...], meta: { page, limit, total, totalPages } }`. Use the shared `PaginationDto` + `paginate()` helper from `src/common` rather than reimplementing paging.

## Roles

- **Admin** — products, tax config, users, reports (full access).
- **Cashier (User)** — billing, payments, invoice printing, order history.

Roles are seeded by `npm run seed` (creates default roles + a default admin, credentials `admin / Admin@123` — must be changed after first login, never hardcode this elsewhere).

## Conventions to preserve

- All routes gated with `JwtAuthGuard` + `@Roles('ADMIN')`.
- `DELETE /users/:id` is a soft delete (set `isActive=false` / deletedAt), never a hard row delete — matches the `products` module's soft-delete pattern.
- Password reset hashes with bcrypt before persisting; bump the user's `tokenVersion` on reset so existing refresh tokens are invalidated.
- Never return `passwordHash` (or any credential field) in `UserEntity`/Swagger responses.
- Validate `roleName` against the seeded `Role` table — reject unknown roles with a 400, don't silently create new roles from this endpoint.
