# Pub & Resto-Bar ERP — Requirements & Gap Analysis

Target product: evolve this **POS Billing App** (NestJS + Prisma + PostgreSQL backend,
Flutter Web/Android/iOS frontend) into a multi-tenant SaaS ERP for pubs and resto-bars.

Status legend: ✅ exists · 🟡 partial (extend) · ❌ new

---

## 0. Current State of the Codebase (Nov 2026)

| Area | What exists | Status |
|---|---|---|
| Auth | JWT access/refresh, Google OAuth, login-method config | ✅ |
| Users & roles | `Role` (ADMIN/USER), `UserFeatureGrant` per user on `AppFeature` enum (DASHBOARD, PRODUCTS, TAX, USERS, ORDERS, APPEARANCE) | 🟡 |
| Products | CRUD, Excel import (`ProductImportLog`), images, featured items | 🟡 |
| Tax | Global tax + per-product override | 🟡 |
| Orders / billing / payments | Order + items, payments, payment method + gateway config | 🟡 |
| Invoice | Country profiles, counters, PDF (Puppeteer), download log | ✅ |
| Reports | Dashboard (revenue, top products) | 🟡 |
| Localisation | `TranslationKey/Value`, bundle/import/export API, `UserLocalePreference` | 🟡 — ~21 Flutter files still contain hard-coded strings |
| Theming / branding | Token-based `Theme`, `ThemeAssignment` per platform, `BrandLogo`, theme editor | ✅ |
| Kiosk | `KioskConfig`, kiosk display screen | 🟡 |
| Audit | `AuditLog` table | 🟡 — coverage incomplete |
| Logging | Nest `Logger` + `LoggingInterceptor` (plain text) | 🟡 |
| Tests | Backend: 3 specs (money, tax, themes). Frontend: placeholder only. No CI | ❌ |
| Multi-tenancy | **No `Tenant` / `Outlet` model** — single business assumed | ❌ |

### Foundational gaps (must be fixed before adding modules)
1. **Tenant & Outlet model** — add `Tenant`, `Outlet`, `Zone`; add `tenantId` (and `outletId` where relevant) to every business table; tenant-scoped Prisma middleware / row-level security.
2. **Persona-based RBAC** — replace ADMIN/USER with personas (Super Admin, Tenant Admin, Outlet Admin, Manager, Cashier, Captain, Waiter, Bartender, Chef, Storekeeper, Accountant, HR) + fine-grained permissions.
3. **Feature catalog** — replace the hard-coded `AppFeature` enum with a data-driven `Feature` table + plan entitlements (§18).
4. **Real-time layer** — WebSocket gateway (Socket.IO) + Redis for KDS, queue, displays.
5. **Job queue** — BullMQ + Redis for WhatsApp, AI imports, reports, sync.
6. **Testing & CI pipeline** (§22) and **observability** (§21).

---

## 1. Module Requirements Summary

Each module is a toggleable feature (`feature key`) governed by §18.

| # | Module | Feature key(s) | Status |
|---|---|---|---|
| 1.1 | POS: dine-in/bar/takeaway/delivery, floor plan, table merge/split/transfer, bar tabs with pre-auth & limits, modifiers, courses, seat-wise ordering, peg/bottle/pitcher selling, bottle locker, happy hours, area price lists, split bills, service charge, tips, void/discount approvals with PIN, cash drawer, offline mode | `pos.*` | 🟡 |
| 1.2 | KDS / bar display: KOT/BOT routing by station, timers, bump/recall, cancellation tickets | `kds` | ❌ |
| 1.3 | Menu: categories, variants, allergens, time/channel menus, 86'd items, tax category, recipes (BOM) & yields | `menu.*` | 🟡 |
| 1.4 | Inventory: multi-location, UoM conversions, liquor open-bottle stock, variance & pour cost, kegs, empties, batches/expiry, wastage, stock audits, par levels, FIFO/WAC | `inventory.*` | ❌ |
| 1.5 | Procurement: vendors, PR → PO → GRN → invoice, 3-way match, debit notes, AP ageing, licensed suppliers | `procurement` | ❌ |
| 1.6 | Compliance: liquor licence & hours, excise registers, age prompt, dry days, GST/VAT, e-invoice, fiscal printers | `compliance.*` | 🟡 (invoice profiles) |
| 1.7 | CRM & loyalty: profiles, points/tiers, memberships, house accounts, campaigns, consent, feedback | `crm.*` | ❌ |
| 1.8 | Reservations & events: bookings, deposits, no-shows, ticketing/cover charge, banquets, guest lists | `reservations`, `events` | ❌ |
| 1.9 | Online channels: QR ordering, aggregators, own ordering, menu boards | `qr_ordering`, `aggregators` | 🟡 (kiosk) |
| 1.10 | Staff & HR: rosters, clock-in, attendance, tip pooling, payroll inputs, performance | `hr.*` | ❌ |
| 1.11 | Accounting: CoA, GL, AP/AR, bank recon, expenses, X/Z reports, day lock, P&L, Tally/Xero export | `accounting` | ❌ |
| 1.12 | Multi-outlet: central menu/pricing, central kitchen, franchise royalty, consolidated reports | `multi_outlet` | ❌ |
| 1.13 | Reports & analytics: sales cuts, menu engineering, pour/food cost, variance, void audit, covers, heatmaps | `reports.*` | 🟡 |
| 1.14 | Hardware & integrations: ESC/POS printers, drawers, KDS, EDC, scales, dispensers, SMS/WhatsApp, gateways | `hardware.*` | 🟡 |
| 1.15 | **Walk-in queue & tokens**: token on full house, WhatsApp token + ETA, waiting monitor, call → WhatsApp + highlight, grace/no-show, bar-while-waiting tab, smart table matching | `walkin_queue`, `walkin_queue.whatsapp` | ❌ |
| 1.16 | **Digital signage & brand ads**: screens per zone, playlists/dayparting, share of voice, stock-aware ads, sponsors/campaigns, proof-of-play, sales-lift, QR-to-order, liquor-ad compliance rules & overlays | `signage`, `signage.brand_campaigns`, `signage.brand_portal` | ❌ |
| 1.17 | **Display Control Center** (Admin persona only): unified device registry, device modes (ADS / QUEUE / MENU / KIOSK / KDS / CUSTOMER / SPLIT), live dashboard & thumbnails, remote commands, auto mode-switching, central compliance rules, single Flutter player app | `display_control_center` | 🟡 (kiosk display) |
| 1.18 | **SaaS subscription & entitlements** (§18) | `platform.*` | 🟡 (per-user grants) |
| 1.19 | **AI Assistant panel** (§19) | `ai_assistant` | ❌ |
| 1.20 | **Localisation everywhere** (§20) | core | 🟡 |
| 1.21 | **Theming everywhere + AI theming** (§20) | core / `ai_assistant.theming` | 🟡 |
| 1.22 | **Central logging & live monitoring with consent** (§21) | `support.monitoring` | ❌ |
| 1.23 | **Unit + runtime tests for every feature** (§22) | engineering | ❌ |

Detailed functional requirements for 1.1–1.17 are as agreed in the design discussion; the
sections below specify the platform-level requirements in full.

---

## 18. SaaS Subscription & Feature Entitlements

- **Evaluation chain:** Platform release → Tenant plan + add-ons → Tenant Admin toggle → Outlet toggle → Persona permission. Feature is usable only if all allow.
- **Feature catalog** (`feature` table): key, module, dependencies, limits, status (beta/GA). Dependency enforcement on enable/disable.
- **Plans:** Starter / Growth / Pro / Enterprise + add-ons (WhatsApp packs, screens, AI credits, aggregators). Limits: outlets, users, devices, terminals, WhatsApp msgs, AI credits, storage.
- **Billing lifecycle:** trials, monthly/annual, proration, coupons, GST SaaS invoices, Razorpay/Stripe subscriptions, dunning → grace → read-only → suspend (never delete data).
- **Downgrade:** data retained read-only; devices fall back to allowed modes; over-limit selection.
- **Consoles:** Platform console (vendor), Tenant subscription page (Admin persona), locked-feature upsell (admins only).
- **Enforcement:** `@RequireFeature()` / `@CheckLimit()` guards, Redis entitlement cache, frontend entitlement map drives routes/menus, device modes filtered.
- **Data:** `plan`, `plan_feature`, `plan_limit`, `addon`, `subscription`, `subscription_addon`, `tenant_feature_override`, `outlet_feature_toggle`, `usage_meter`.

## 19. AI Assistant Panel

- **Placement:** context-aware side panel on every admin screen + onboarding wizard. Admin persona; entitlement `ai_assistant`.
- **Uploads:** Excel/CSV/PDF/Word/images (OCR & vision) for menu, liquor SKUs, recipes, inventory, vendors, employees, tables/floor plan, customers (with consent), taxes, offers, displays, **themes**, **translations**.
- **Workflow:** upload → parse → AI column mapping (confidence) → normalise/enrich → validate → **editable preview + diff** → admin approves → transactional apply via the same service APIs → summary → undo (change set rollback).
- **Natural-language config:** e.g. "happy hour Mon–Thu 5–8 pm 30% off beer", "switch entrance TVs to queue mode after 8 pm Fri/Sat".
- **Onboarding interview** → recommended feature/plan configuration + setup checklist.
- **Safety:** AI proposes only; human approves every write; runs with user's permissions & tenant entitlements; full audit ("via AI by {user}"); no passwords imported (invite/PIN flow); PII masked; tenant data not used for training; file retention policy.
- **Tech:** Claude via Anthropic API with tool use (tools map to backend services: `propose_menu_items`, `propose_employees`, `propose_theme`, `propose_translations`, …); output validated against DTOs; streaming; metered AI credits.
- **Data:** `ai_session`, `ai_message`, `file_upload`, `import_job`, `change_set`, `change_set_item`, `column_mapping_profile`.

## 20. Localisation & Theming on Every Screen

### 20.1 Localisation (all surfaces)
- **Zero hard-coded user-facing strings** in Flutter: every string resolves through a translation key (`context.t('billing.pay_now')`). Enforced by a CI lint check (§22).
- **Surfaces covered:** POS, admin, KDS, kiosk, table tablets, queue monitor, signage overlays, customer-facing display, invoices/receipts, KOT/BOT prints, WhatsApp/SMS templates, emails, PDF reports, backend error messages (error codes → localised text), AI assistant replies.
- **Locale resolution:** user preference → device setting (displays/kiosks) → outlet default → tenant default → `en`. Guests on kiosk/QR/queue can switch language.
- **Formats:** numbers, currency, dates/times, time zones per outlet via `intl`; **RTL** layout support (Arabic/Hebrew/Urdu).
- **Translation management:** existing key/value store + import/export; missing-key report; fallback chain; versioned bundles cached offline (Hive); hot reload of bundles without app restart.
- **AI translation:** AI assistant drafts missing translations (glossary-aware: brand/liquor names untranslated), shown as a change set for approval; pseudo-locale (`xx-PSEUDO`) for testing truncation.

### 20.2 Theming (all surfaces)
- **Every widget reads design tokens** (existing v1 token contract); no hard-coded colours, fonts, radii, spacing. CI lint flags `Color(0x…)` / `Colors.*` outside the theme layer.
- **Assignment scope:** tenant → outlet → platform (existing) → **device mode / individual device** (KDS dark high-contrast, signage brand theme, kiosk theme) → user light/dark preference.
- **Brand consistency:** themes linked to branding (logos) and applied to receipts/invoices and display overlays.
- **AI theming:** Admin can ask "make a theme from our logo", upload a logo/photo/brand guide or describe a mood ("dark neon sports-bar"). AI extracts palette, generates a full token set, **validates WCAG AA contrast** for all text/background pairs, shows live preview across POS / KDS / kiosk / signage, and saves as a draft theme for approval. It can also adjust an existing theme ("bigger buttons for the bar tablet", "warmer accents").
- **Safety:** AI never activates a theme directly; activation remains an explicit admin action; last-known-good theme fallback (existing behaviour) retained.

## 21. Central Logging & Live Monitoring (consent-based)

Goal: the vendor support team can see and resolve customer issues quickly from **one place**, but only when the **customer allows it**.

### 21.1 Consent & privacy
- Tenant Admin chooses a **diagnostics level** per tenant/outlet: `OFF` · `ERRORS_ONLY` · `STANDARD` (errors + performance + device health) · `FULL_DIAGNOSTIC` (verbose logs, time-boxed, e.g. 24 h) · `LIVE_SUPPORT_SESSION` (support can view live logs/screens of a device; requires explicit per-session approval, auto-expires).
- Consent changes are audited; current level visible in the app; revoke anytime.
- **PII redaction at source**: phone numbers, names, emails, card data, tokens masked before leaving the device/server. Never log passwords, PINs, payment card data, or AI-uploaded raw files.
- Data residency per tenant region; retention configurable (e.g. 30 days logs, 13 months metrics).

### 21.2 What is collected
- **Backend:** structured JSON logs (pino via `nestjs-pino`) with `tenantId`, `outletId`, `userId`(hashed), `requestId`, `traceId`, feature key; OpenTelemetry traces; Prometheus metrics (latency, error rate, queue depth, DB pool, WhatsApp/AI call stats).
- **Frontend (Flutter, all devices):** uncaught errors, Flutter errors, network failures, slow frames, app version, device mode, offline/sync state; batched upload, buffered offline.
- **Devices / displays:** heartbeat, current mode & config version, playback errors, storage, printer status.
- **Business health signals:** failed payments, KOT print failures, sync backlog, WhatsApp delivery failures.

### 21.3 Support / Monitoring Console (one place, vendor side)
- Tenant/outlet health overview (green/amber/red), active incidents, error trends, release versions in the field.
- Drill-down: per tenant → outlet → device → session; **live log tail** (when consented), trace viewer, recent errors with stack traces.
- **Remote diagnostics actions** (consented, audited): fetch device logs, refresh config, clear cache, restart app, toggle verbose logging, roll back a feature flag.
- Alerting: thresholds & anomaly alerts to on-call (email/Slack/WhatsApp); auto-create support ticket linked to tenant.
- Tenant-side view: customers see their own system status and can raise a ticket with logs attached in one click.

### 21.4 Tech
- OpenTelemetry SDK (backend) → collector → Grafana stack (Loki logs, Tempo traces, Prometheus/Mimir metrics) or a managed equivalent; Sentry/GlitchTip for error grouping (backend + Flutter).
- Consent level enforced at the SDK and the collector (drop by tenant attribute).

## 22. Testing: Unit + Runtime Tests for Every Feature

### 22.1 Definition of Done for every feature
A feature cannot be merged unless it includes:
- **Backend unit tests** (Jest) for services, guards, calculation logic — target ≥ 80% line coverage on the module, 100% on money/tax/stock calculations.
- **Backend integration tests** against a real PostgreSQL (Testcontainers) for repositories, migrations, entitlement guards.
- **API e2e tests** (supertest) for each endpoint incl. auth, permissions and feature-toggle on/off.
- **Flutter unit + widget tests** for controllers/providers and screens; **golden tests** for key screens in light/dark theme and in at least two locales (one RTL) + pseudo-locale.
- **Flutter integration tests** (`integration_test`) for critical flows: login → bill → pay → print, token queue call, display mode switch.
- **Entitlement matrix tests:** each feature tested enabled and disabled; disabled must return 403 / hide UI.

### 22.2 Runtime tests on every change (CI/CD)
- **On every push / PR (GitHub Actions):** lint (incl. hard-coded string & colour checks), type-check, backend unit + integration + e2e, Flutter analyze + unit/widget/golden tests, Prisma migration check, coverage gate, dependency vulnerability scan.
- **On merge to main:** build & deploy to **staging** → run **runtime smoke/E2E suite** (Playwright for Flutter web, API smoke via supertest/k6) against the deployed app with seeded test tenant → promote to production only if green.
- **After production deploy:** automated smoke tests + health checks; **synthetic monitoring** runs key journeys every 5–15 min (login, create order, invoice PDF, queue token, display heartbeat) and alerts via §21.
- **Canary / feature-flag rollout:** new features released to beta tenants first; automatic rollback if error rate rises.
- **Performance tests** (k6) nightly: bill < 1 s, KOT < 2 s, display update < 1 s.

### 22.3 Current gap
Backend has 3 spec files; frontend has a placeholder test; no CI. Phase 0 must add the test harness, CI workflow, and tests for existing modules before new modules are built.

---

## 23. Non-Functional Requirements (consolidated)
Performance (bill < 1 s, KOT < 2 s), offline POS with sync, 99.9% cloud availability, multi-tenant isolation, RBAC + PIN overrides, immutable audit, PCI-DSS (no card storage), GDPR / India DPDP, daily backups + PITR, touch-first UI with dark mode, localisation & theming on every surface, observability with consent, automated tests on every change.

---

## 24. Phased Implementation Plan (in this repo)

| Phase | Scope |
|---|---|
| **0 — Platform foundation** | Tenant/Outlet/Zone model + tenant scoping · persona RBAC · feature catalog + entitlement guards (migrate `AppFeature`) · localisation of all existing screens + lint · theme-token lint · structured logging + OpenTelemetry + Flutter error reporting + consent levels · test harness + GitHub Actions CI · Redis + BullMQ + WebSocket gateway |
| **1 — Core bar POS + displays** | Floor plan/tables, bar tabs, liquor units, modifiers, happy hours, KOT/BOT + KDS, void/discount approvals, day close · Display Control Center + single player app (kiosk/KDS/menu modes) |
| **2 — Stock & compliance** | Recipes/BOM, multi-location inventory, liquor variance & pour cost, procurement, excise registers |
| **3 — Guest & growth** | Walk-in queue + WhatsApp, digital signage & brand campaigns, CRM/loyalty, reservations/events, QR ordering, aggregators · subscription billing · AI Assistant (imports, NL config, theming, translations) |
| **4 — Enterprise** | Accounting, HR/payroll, multi-outlet & central kitchen, AI insights, support monitoring console enhancements |

Each phase ships with its unit, integration, e2e and runtime tests per §22.
