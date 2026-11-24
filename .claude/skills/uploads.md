---
name: uploads
description: Work on the Enterprise POS backend's uploads/storage module — the StorageService abstraction used for product image uploads (local filesystem now, S3-swappable later). Use whenever the user asks to add/modify file storage, image uploads, or wants to implement/swap in an S3 storage backend, or touches backend/src/uploads.
---

# Uploads / Storage Module (Enterprise POS backend)

NestJS feature module providing a single storage abstraction consumed by other modules (currently `products`, for images).

## Module layout

```
src/uploads/
├── storage.interface.ts     # StorageService contract (upload, delete, getUrl, ...)
├── local-storage.service.ts # current implementation → writes to ./uploads
├── uploads.module.ts         # binds StorageService → LocalStorageService
```

## Design contract (docs/ARCHITECTURE.md — Storage abstraction)

`StorageService` is an interface; `LocalStorageService` is the only implementation today, writing to `./uploads` on the local filesystem. Swapping to S3 later means:

1. Add an `S3StorageService` implementing the exact same `StorageService` interface.
2. Change one DI provider binding in `uploads.module.ts` (or via config/env flag).
3. **No call-site changes anywhere else in the codebase.**

## Conventions to preserve

- Every consumer (e.g. `products.controller.ts` handling `POST /products/:id/image`) must depend on the `StorageService` interface/injection token, never on `LocalStorageService` directly and never write to `fs` inline.
- File validation (allowed mime types/extensions, max size) belongs in this module or a shared pipe/interceptor used by every upload endpoint — keep it centralized so it stays consistent as more upload endpoints are added (e.g. Excel import in `products` also flows through here for the raw file handling, even though parsing is `products`' job).
- Stored file paths/keys returned by `StorageService` should be opaque references (not raw local paths leaked to the client) so the S3 swap doesn't change the API contract for consumers.
- When implementing S3 (docs/ROADMAP.md Phase 7 — Hardening), add config via `@nestjs/config` + `.env` (bucket, region, credentials) rather than hardcoding, matching the rest of the app's environment-based config pattern.
