---
name: auth
description: Work on the Enterprise POS backend's authentication module (login, refresh, logout, current-user, JWT issuing, password hashing, guards). Use whenever the user asks to add/modify/debug login, JWT access/refresh tokens, RolesGuard/JwtAuthGuard, password reset, or anything under backend/src/auth. Always consult before editing files in that module or wiring new protected routes.
---

# Auth Module (Enterprise POS backend)

NestJS feature module responsible for authenticating users and issuing JWTs.
Stack: NestJS, Prisma, PostgreSQL, bcrypt, `@nestjs/jwt`.

## Module layout (follow exactly — matches every other module in this repo)

```
src/auth/
├── dto/                 # LoginDto, RefreshDto, ResetPasswordDto — class-validator rules
├── entities/             # Swagger response models (e.g. AuthResponseEntity)
├── auth.controller.ts    # HTTP layer only: routing, guards, Swagger decorators
├── auth.service.ts       # business logic (verify password, issue/rotate tokens)
├── auth.repository.ts    # Prisma data access (Repository Pattern) — no business logic here
└── auth.module.ts        # DI wiring
```

Never put Prisma calls in the controller or business logic in the repository — keep the three layers strictly separated, same as `products`, `orders`, etc.

## Endpoints (base `/api/v1`, see docs/API.md)

| Method | Path | Role | Notes |
|---|---|---|---|
| POST | `/auth/login` | public | `{ username, password }` → `{ accessToken, refreshToken, user }` |
| POST | `/auth/refresh` | public | `{ refreshToken }` → `{ accessToken }` |
| POST | `/auth/logout` | auth | revokes refresh tokens |
| GET | `/auth/me` | auth | current user profile |

## Authentication flow (docs/ARCHITECTURE.md §5 — implement to this spec)

1. `POST /auth/login {username, password}` → verify bcrypt hash → issue `accessToken` (15m expiry) + `refreshToken` (7d expiry).
2. Client stores tokens (Hive on the Flutter side); sends `Authorization: Bearer <access>`.
3. On 401 the client calls `POST /auth/refresh {refreshToken}` → new access token.
4. `RolesGuard` checks `@Roles('ADMIN')` metadata against the JWT's `role` claim.
5. `POST /auth/logout` revokes the refresh token by bumping the user's `tokenVersion` (invalidates all outstanding refresh tokens for that user — do not implement a separate blacklist table unless asked).
6. Admin password reset lives in the `users` module: `PATCH /users/:id/reset-password` (ADMIN only), not here.

## Cross-cutting pieces this module depends on (src/common)

- `JwtAuthGuard` — validates the access token, attaches `req.user`.
- `RolesGuard` — reads `@Roles(...)` metadata, compares to `req.user.role`.
- `@Public()` decorator — marks a route as bypassing `JwtAuthGuard` (used on login/refresh).
- `@CurrentUser()` decorator — pulls the authenticated user off the request.
- Global `ValidationPipe` (whitelist + transform) validates all DTOs — don't hand-roll validation.
- `AllExceptionsFilter` produces the standard error envelope: `{ statusCode, message, error, path, timestamp }`.

## Conventions to preserve

- Passwords are always hashed with bcrypt; never log or return plaintext passwords or hashes.
- Access tokens are short-lived (15m), refresh tokens long-lived (7d) — don't change these defaults without being asked.
- `tokenVersion` on the `User` row is the mechanism for invalidating refresh tokens; increment it on logout and on password reset.
- Every new protected route: apply `JwtAuthGuard` (usually global) + `@Roles('ADMIN')` if admin-only, and mark public routes explicitly with `@Public()`.
- Unit tests belong in `auth.service.spec.ts` — cover login success/failure, refresh rotation, and `RolesGuard` behavior (per docs/ROADMAP.md Phase 1).
