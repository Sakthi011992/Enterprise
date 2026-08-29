---
name: common-backend
description: Consult before touching cross-cutting backend infrastructure in the Enterprise POS API — guards (JwtAuthGuard, RolesGuard), decorators (@Roles, @CurrentUser, @Public), interceptors (LoggingInterceptor, TransformInterceptor), the global exception filter, the global validation pipe, or the shared pagination helper. Also consult when adding a brand-new feature module, since every module must follow the same layering and reuse these pieces. Covers backend/src/common.
---

# Common / Cross-Cutting Backend Infrastructure (Enterprise POS)

Shared building blocks every feature module (`auth`, `users`, `products`, `tax`, `orders`, `payments`, `invoice`, `reports`, `uploads`) is built on top of. Read this before creating a new module or modifying auth/validation/error-handling behavior, since a change here affects every module at once.

## Standard module layering (apply to every new feature module)

```
module/
├── dto/                 # request/response shapes + class-validator rules
├── entities/             # Swagger response models
├── <feature>.controller.ts   # HTTP layer only (routing, guards, Swagger)
├── <feature>.service.ts      # business logic (use-cases)
├── <feature>.repository.ts   # data access (Prisma) — Repository Pattern
└── <feature>.module.ts       # DI wiring
```
Controllers never call Prisma directly; services never import `@nestjs/common` HTTP decorators; repositories contain no business rules. This is a hard convention across the whole backend.

## Guards

- `JwtAuthGuard` — validates the JWT access token, populates `req.user`. Applied globally; opt out per-route with `@Public()`.
- `RolesGuard` — reads `@Roles('ADMIN')` metadata and compares against `req.user.role`. Combine with `JwtAuthGuard`, applied after it.

## Decorators

- `@Roles('ADMIN')` — marks a route/handler as requiring a specific role.
- `@CurrentUser()` — param decorator that extracts the authenticated user from the request.
- `@Public()` — marks a route as bypassing `JwtAuthGuard` (used for `/auth/login`, `/auth/refresh`).

## Interceptors

- `LoggingInterceptor` — logs request/response plus timing for every request.
- `TransformInterceptor` — wraps successful responses in the app's uniform envelope. Don't hand-roll response shaping in individual controllers; let this interceptor do it.

## Filters

- `AllExceptionsFilter` — catches all thrown exceptions and produces the standard error envelope:
  ```
  { "statusCode": 400, "message": "…", "error": "Bad Request", "path": "/api/v1/…", "timestamp": "…" }
  ```
  Throw standard Nest `HttpException` subclasses (`BadRequestException`, `NotFoundException`, etc.) from services/controllers and let this filter format them — don't construct the error envelope manually.

## Pipes

- Global `ValidationPipe` configured with `whitelist: true` and `transform: true` — DTOs are auto-validated and coerced. Define validation entirely via `class-validator`/`class-transformer` decorators on DTOs; don't add manual validation in controllers.

## Pagination

- Shared `PaginationDto` (`page`, `limit`, `search`) + a `paginate()` helper used by every list endpoint.
- Standard contract for all list endpoints: request `?page=1&limit=20&search=<q>`, response `{ "data": [...], "meta": { "page": 1, "limit": 20, "total": 0, "totalPages": 0 } }`. Reuse this helper rather than reimplementing pagination per module — every module in this repo (`users`, `products`, `orders`, ...) relies on it being consistent.

## API versioning & docs

- All routes are prefixed `/api/v1` (URI-based versioning). Swagger docs are auto-generated and served at `/api/docs` — decorate new DTOs/controllers with the appropriate `@nestjs/swagger` decorators so they show up correctly.

## When adding a new module

1. Scaffold the standard layout above.
2. Wire `JwtAuthGuard` (usually global already) + `@Roles()` as needed; mark public routes with `@Public()`.
3. Use `PaginationDto`/`paginate()` for any list endpoint.
4. Throw `HttpException` subtypes for errors; never build the error envelope manually.
5. Add unit tests for the service layer (business logic), following the pattern used in `auth.service.spec.ts` / calculation-engine tests in `orders`.
