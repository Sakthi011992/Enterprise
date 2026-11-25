-- Phase 1 foundation: tenants, outlets, personas, permissions, devices, notifications,
-- password reset tokens, staff PINs. Adds tenantId to business tables and outletId to orders.
-- Data seeded here must match backend/src/common/permissions/catalog.ts.

-- CreateEnum
CREATE TYPE "AccessLevel" AS ENUM ('NONE', 'VIEW', 'REQUEST', 'LIMITED', 'APPROVE', 'EDIT');

-- CreateEnum
CREATE TYPE "PersonaLoginMethod" AS ENUM ('PASSWORD', 'PIN');

-- CreateEnum
CREATE TYPE "DeviceType" AS ENUM ('POS_TABLET', 'KDS', 'TV', 'KIOSK', 'PRINTER', 'PHONE');

-- CreateTable
CREATE TABLE "tenants" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "tenants_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "outlets" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "address" TEXT,
    "timezone" TEXT NOT NULL DEFAULT 'Asia/Kolkata',
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "outlets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "personas" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "homeRoute" TEXT NOT NULL DEFAULT '/dashboard',
    "loginMethod" "PersonaLoginMethod" NOT NULL DEFAULT 'PASSWORD',
    "isSystem" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "personas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "permissions" (
    "key" TEXT NOT NULL,
    "group" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "description" TEXT,
    "limitUnit" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "permissions_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "persona_permissions" (
    "personaId" TEXT NOT NULL,
    "permissionKey" TEXT NOT NULL,
    "level" "AccessLevel" NOT NULL DEFAULT 'NONE',
    "limitValue" DECIMAL(12,2),

    CONSTRAINT "persona_permissions_pkey" PRIMARY KEY ("personaId", "permissionKey")
);

-- CreateTable
CREATE TABLE "user_outlets" (
    "userId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "personaId" TEXT NOT NULL,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_outlets_pkey" PRIMARY KEY ("userId", "outletId")
);

-- CreateTable
CREATE TABLE "staff_pins" (
    "userId" TEXT NOT NULL,
    "pinHash" TEXT NOT NULL,
    "failedAttempts" INTEGER NOT NULL DEFAULT 0,
    "lockedUntil" TIMESTAMP(3),
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "staff_pins_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "type" "DeviceType" NOT NULL,
    "keyHash" TEXT NOT NULL,
    "lastSeenAt" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT,
    "userId" TEXT,
    "permissionKey" TEXT,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT,
    "data" JSONB,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "password_reset_tokens" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "password_reset_tokens_pkey" PRIMARY KEY ("id")
);

-- AlterTable: existing tables gain tenantId (nullable until backfilled)
ALTER TABLE "users" ADD COLUMN "tenantId" TEXT, ADD COLUMN "displayName" TEXT, ADD COLUMN "phone" TEXT;

-- AlterTable
ALTER TABLE "products" ADD COLUMN "tenantId" TEXT;

-- AlterTable
ALTER TABLE "global_tax_settings" ADD COLUMN "tenantId" TEXT;

-- AlterTable
ALTER TABLE "orders" ADD COLUMN "tenantId" TEXT, ADD COLUMN "outletId" TEXT;

-- AlterTable
ALTER TABLE "product_import_logs" ADD COLUMN "tenantId" TEXT;

-- AlterTable
ALTER TABLE "audit_logs" ADD COLUMN "tenantId" TEXT;

-- Default tenant, main outlet
INSERT INTO "tenants" ("id", "name", "slug", "isActive", "createdAt", "updatedAt")
VALUES (gen_random_uuid()::text, 'Default venue', 'default', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO "outlets" ("id", "tenantId", "name", "code", "address", "timezone", "isActive", "createdAt", "updatedAt")
SELECT gen_random_uuid()::text, t."id", 'Main outlet', 'MAIN', NULL::TEXT, 'Asia/Kolkata', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "tenants" t
WHERE t."slug" = 'default';

-- Permission catalog (PLAN.md 1.1)
INSERT INTO "permissions" ("key", "group", "label", "description", "limitUnit", "sortOrder") VALUES
  ('sales.orders.take', 'Sales', 'Take orders & send KOT/BOT', NULL, NULL, 1),
  ('sales.payments.take', 'Sales', 'Take payment & close bill', NULL, NULL, 2),
  ('sales.discount.give', 'Sales', 'Give discount', NULL, 'percent', 3),
  ('sales.void', 'Sales', 'Void item / bill', NULL, NULL, 4),
  ('sales.tab.open', 'Sales', 'Open bar tab', NULL, 'inr', 5),
  ('menu.edit', 'Menu & stock', 'Edit menu & prices', NULL, NULL, 6),
  ('menu.mark86', 'Menu & stock', 'Mark item out of stock (86)', NULL, NULL, 7),
  ('stock.count', 'Menu & stock', 'Stock count & wastage', NULL, NULL, 8),
  ('stock.purchaseOrders', 'Menu & stock', 'Purchase orders', NULL, NULL, 9),
  ('guests.queue', 'Guests & displays', 'Walk-in queue', NULL, NULL, 10),
  ('displays.control', 'Guests & displays', 'Display Control Center', NULL, NULL, 11),
  ('reports.view', 'Reports', 'Reports & day close', NULL, NULL, 12),
  ('admin.users', 'Admin', 'Users, personas & permissions', NULL, NULL, 13),
  ('admin.settings', 'Admin', 'Outlets, tax, devices & settings', NULL, NULL, 14),
  ('admin.themes', 'Admin', 'Themes & branding', NULL, NULL, 15);

-- Default personas for the default tenant (PLAN.md 1.2)
INSERT INTO "personas" ("id", "tenantId", "key", "name", "description", "homeRoute", "loginMethod", "isSystem", "createdAt", "updatedAt")
SELECT gen_random_uuid()::text, t."id", v."key", v."name", NULL::TEXT, v."homeRoute", v."loginMethod"::"PersonaLoginMethod", v."isSystem", CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "tenants" t
CROSS JOIN (VALUES
  ('admin', 'Admin', '/dashboard', 'PASSWORD', true),
  ('manager', 'Manager', '/dashboard', 'PASSWORD', false),
  ('cashier', 'Cashier', '/pos', 'PIN', false),
  ('captain', 'Captain', '/pos', 'PIN', false),
  ('waiter', 'Waiter', '/pos', 'PIN', false),
  ('bartender', 'Bartender', '/pos', 'PIN', false),
  ('chef', 'Chef', '/menu', 'PIN', false),
  ('storekeeper', 'Storekeeper', '/menu', 'PIN', false),
  ('kiosk', 'Kiosk display', '/kiosk', 'PASSWORD', true)
) AS v("key", "name", "homeRoute", "loginMethod", "isSystem")
WHERE t."slug" = 'default';

-- Default matrix. Only non-NONE grants are stored; missing rows mean NONE (PLAN.md 1.2).
INSERT INTO "persona_permissions" ("personaId", "permissionKey", "level", "limitValue")
SELECT p."id", v."permissionKey", v."level"::"AccessLevel", v."limitValue"::DECIMAL(12,2)
FROM "personas" p
JOIN "tenants" t ON t."id" = p."tenantId" AND t."slug" = 'default'
JOIN (VALUES
  ('admin', 'sales.orders.take', 'EDIT', NULL),
  ('admin', 'sales.payments.take', 'EDIT', NULL),
  ('admin', 'sales.discount.give', 'EDIT', NULL),
  ('admin', 'sales.void', 'EDIT', NULL),
  ('admin', 'sales.tab.open', 'EDIT', NULL),
  ('admin', 'menu.edit', 'EDIT', NULL),
  ('admin', 'menu.mark86', 'EDIT', NULL),
  ('admin', 'stock.count', 'EDIT', NULL),
  ('admin', 'stock.purchaseOrders', 'EDIT', NULL),
  ('admin', 'guests.queue', 'EDIT', NULL),
  ('admin', 'displays.control', 'EDIT', NULL),
  ('admin', 'reports.view', 'EDIT', NULL),
  ('admin', 'admin.users', 'EDIT', NULL),
  ('admin', 'admin.settings', 'EDIT', NULL),
  ('admin', 'admin.themes', 'EDIT', NULL),
  ('manager', 'sales.orders.take', 'EDIT', NULL),
  ('manager', 'sales.payments.take', 'EDIT', NULL),
  ('manager', 'sales.discount.give', 'LIMITED', 30),
  ('manager', 'sales.void', 'APPROVE', NULL),
  ('manager', 'sales.tab.open', 'EDIT', NULL),
  ('manager', 'menu.edit', 'EDIT', NULL),
  ('manager', 'menu.mark86', 'EDIT', NULL),
  ('manager', 'stock.count', 'EDIT', NULL),
  ('manager', 'stock.purchaseOrders', 'APPROVE', NULL),
  ('manager', 'guests.queue', 'EDIT', NULL),
  ('manager', 'displays.control', 'LIMITED', NULL),
  ('manager', 'reports.view', 'EDIT', NULL),
  ('manager', 'admin.settings', 'VIEW', NULL),
  ('manager', 'admin.themes', 'VIEW', NULL),
  ('cashier', 'sales.orders.take', 'EDIT', NULL),
  ('cashier', 'sales.payments.take', 'EDIT', NULL),
  ('cashier', 'sales.discount.give', 'LIMITED', 10),
  ('cashier', 'sales.void', 'REQUEST', NULL),
  ('cashier', 'sales.tab.open', 'LIMITED', 5000),
  ('cashier', 'menu.edit', 'VIEW', NULL),
  ('cashier', 'guests.queue', 'EDIT', NULL),
  ('cashier', 'reports.view', 'LIMITED', NULL),
  ('captain', 'sales.orders.take', 'EDIT', NULL),
  ('captain', 'sales.payments.take', 'VIEW', NULL),
  ('captain', 'sales.discount.give', 'LIMITED', 10),
  ('captain', 'sales.void', 'REQUEST', NULL),
  ('captain', 'sales.tab.open', 'LIMITED', 5000),
  ('captain', 'menu.edit', 'VIEW', NULL),
  ('captain', 'menu.mark86', 'EDIT', NULL),
  ('captain', 'guests.queue', 'EDIT', NULL),
  ('waiter', 'sales.orders.take', 'EDIT', NULL),
  ('waiter', 'sales.void', 'REQUEST', NULL),
  ('waiter', 'menu.edit', 'VIEW', NULL),
  ('waiter', 'guests.queue', 'VIEW', NULL),
  ('bartender', 'sales.orders.take', 'EDIT', NULL),
  ('bartender', 'sales.payments.take', 'EDIT', NULL),
  ('bartender', 'sales.discount.give', 'LIMITED', 5),
  ('bartender', 'sales.void', 'REQUEST', NULL),
  ('bartender', 'sales.tab.open', 'LIMITED', 10000),
  ('bartender', 'menu.edit', 'VIEW', NULL),
  ('bartender', 'menu.mark86', 'EDIT', NULL),
  ('bartender', 'stock.count', 'EDIT', NULL),
  ('bartender', 'guests.queue', 'VIEW', NULL),
  ('chef', 'menu.edit', 'VIEW', NULL),
  ('chef', 'menu.mark86', 'EDIT', NULL),
  ('chef', 'stock.count', 'EDIT', NULL),
  ('chef', 'stock.purchaseOrders', 'REQUEST', NULL),
  ('storekeeper', 'menu.edit', 'VIEW', NULL),
  ('storekeeper', 'menu.mark86', 'EDIT', NULL),
  ('storekeeper', 'stock.count', 'EDIT', NULL),
  ('storekeeper', 'stock.purchaseOrders', 'EDIT', NULL),
  ('storekeeper', 'reports.view', 'LIMITED', NULL)
) AS v("personaKey", "permissionKey", "level", "limitValue") ON v."personaKey" = p."key";

-- Backfill tenantId on existing rows with the default tenant
UPDATE "users" SET "tenantId" = (SELECT "id" FROM "tenants" WHERE "slug" = 'default') WHERE "tenantId" IS NULL;
UPDATE "products" SET "tenantId" = (SELECT "id" FROM "tenants" WHERE "slug" = 'default') WHERE "tenantId" IS NULL;
UPDATE "global_tax_settings" SET "tenantId" = (SELECT "id" FROM "tenants" WHERE "slug" = 'default') WHERE "tenantId" IS NULL;
UPDATE "orders" SET "tenantId" = (SELECT "id" FROM "tenants" WHERE "slug" = 'default') WHERE "tenantId" IS NULL;
UPDATE "product_import_logs" SET "tenantId" = (SELECT "id" FROM "tenants" WHERE "slug" = 'default') WHERE "tenantId" IS NULL;
UPDATE "audit_logs" SET "tenantId" = (SELECT "id" FROM "tenants" WHERE "slug" = 'default') WHERE "tenantId" IS NULL;

-- Map existing users: ADMIN role -> admin, KIOSK role -> kiosk, USER role -> cashier persona, all at MAIN
INSERT INTO "user_outlets" ("userId", "outletId", "personaId", "isDefault", "createdAt")
SELECT u."id", o."id", p."id", true, CURRENT_TIMESTAMP
FROM "users" u
JOIN "roles" r ON r."id" = u."roleId"
JOIN "outlets" o ON o."tenantId" = u."tenantId" AND o."code" = 'MAIN'
JOIN "personas" p ON p."tenantId" = u."tenantId"
  AND p."key" = CASE r."name" WHEN 'ADMIN' THEN 'admin' WHEN 'KIOSK' THEN 'kiosk' ELSE 'cashier' END;

-- Required tenantId from here on
ALTER TABLE "users" ALTER COLUMN "tenantId" SET NOT NULL;
ALTER TABLE "products" ALTER COLUMN "tenantId" SET NOT NULL;
ALTER TABLE "global_tax_settings" ALTER COLUMN "tenantId" SET NOT NULL;
ALTER TABLE "orders" ALTER COLUMN "tenantId" SET NOT NULL;
ALTER TABLE "product_import_logs" ALTER COLUMN "tenantId" SET NOT NULL;
ALTER TABLE "audit_logs" ALTER COLUMN "tenantId" SET NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "tenants_slug_key" ON "tenants"("slug");

-- CreateIndex
CREATE UNIQUE INDEX "outlets_tenantId_code_key" ON "outlets"("tenantId", "code");

-- CreateIndex
CREATE INDEX "outlets_tenantId_idx" ON "outlets"("tenantId");

-- CreateIndex
CREATE UNIQUE INDEX "personas_tenantId_key_key" ON "personas"("tenantId", "key");

-- CreateIndex
CREATE INDEX "personas_tenantId_idx" ON "personas"("tenantId");

-- CreateIndex
CREATE INDEX "user_outlets_personaId_idx" ON "user_outlets"("personaId");

-- CreateIndex
CREATE UNIQUE INDEX "devices_keyHash_key" ON "devices"("keyHash");

-- CreateIndex
CREATE INDEX "devices_tenantId_idx" ON "devices"("tenantId");

-- CreateIndex
CREATE INDEX "devices_outletId_idx" ON "devices"("outletId");

-- CreateIndex
CREATE INDEX "notifications_tenantId_userId_readAt_idx" ON "notifications"("tenantId", "userId", "readAt");

-- CreateIndex
CREATE UNIQUE INDEX "password_reset_tokens_tokenHash_key" ON "password_reset_tokens"("tokenHash");

-- CreateIndex
CREATE INDEX "password_reset_tokens_userId_idx" ON "password_reset_tokens"("userId");

-- CreateIndex
CREATE INDEX "users_tenantId_idx" ON "users"("tenantId");

-- CreateIndex
CREATE INDEX "products_tenantId_idx" ON "products"("tenantId");

-- CreateIndex
CREATE INDEX "global_tax_settings_tenantId_idx" ON "global_tax_settings"("tenantId");

-- CreateIndex
CREATE INDEX "orders_tenantId_idx" ON "orders"("tenantId");

-- CreateIndex
CREATE INDEX "orders_outletId_idx" ON "orders"("outletId");

-- CreateIndex
CREATE INDEX "product_import_logs_tenantId_idx" ON "product_import_logs"("tenantId");

-- CreateIndex
CREATE INDEX "audit_logs_tenantId_idx" ON "audit_logs"("tenantId");

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "outlets" ADD CONSTRAINT "outlets_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "personas" ADD CONSTRAINT "personas_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "persona_permissions" ADD CONSTRAINT "persona_permissions_personaId_fkey" FOREIGN KEY ("personaId") REFERENCES "personas"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "persona_permissions" ADD CONSTRAINT "persona_permissions_permissionKey_fkey" FOREIGN KEY ("permissionKey") REFERENCES "permissions"("key") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_outlets" ADD CONSTRAINT "user_outlets_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_outlets" ADD CONSTRAINT "user_outlets_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_outlets" ADD CONSTRAINT "user_outlets_personaId_fkey" FOREIGN KEY ("personaId") REFERENCES "personas"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "staff_pins" ADD CONSTRAINT "staff_pins_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "password_reset_tokens" ADD CONSTRAINT "password_reset_tokens_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "global_tax_settings" ADD CONSTRAINT "global_tax_settings_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_import_logs" ADD CONSTRAINT "product_import_logs_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
