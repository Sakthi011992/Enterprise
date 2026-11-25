-- Phase 2 POS core: menu (categories, variants, modifiers, combos, happy hour), floor plan (areas,
-- tables), outlet settings, tax classes, order lifecycle columns, discounts, tickets, printers and
-- print jobs, approvals, day close.
-- Enum values added to OrderStatus here are NOT used in this migration. The column default that
-- starts new orders at OPEN is set in 20261125130100_phase2_order_default.

-- CreateEnum
CREATE TYPE "OrderType" AS ENUM ('DINE_IN', 'BAR_COUNTER', 'TAKEAWAY', 'DELIVERY');

-- CreateEnum
CREATE TYPE "OrderItemStatus" AS ENUM ('NEW', 'SENT', 'SERVED', 'VOIDED');

-- CreateEnum
CREATE TYPE "TicketKind" AS ENUM ('KOT', 'BOT');

-- CreateEnum
CREATE TYPE "TicketStatus" AS ENUM ('QUEUED', 'PRINTED', 'FAILED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "TableStatus" AS ENUM ('FREE', 'OCCUPIED', 'BILL_PRINTED', 'CLEANING', 'RESERVED');

-- CreateEnum
CREATE TYPE "TableShape" AS ENUM ('SQUARE', 'ROUND', 'LONG');

-- CreateEnum
CREATE TYPE "ApprovalType" AS ENUM ('DISCOUNT', 'VOID', 'REFUND', 'NO_SALE');

-- CreateEnum
CREATE TYPE "ApprovalStatus" AS ENUM ('PENDING', 'APPROVED', 'DECLINED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "DiscountType" AS ENUM ('PERCENT', 'FLAT');

-- CreateEnum
CREATE TYPE "PrinterConnection" AS ENUM ('LAN', 'USB', 'BLUETOOTH');

-- CreateEnum
CREATE TYPE "PrintJobKind" AS ENUM ('TICKET', 'BILL', 'REPORT', 'DRAWER', 'TEST');

-- CreateEnum
CREATE TYPE "PrintJobStatus" AS ENUM ('QUEUED', 'SENT', 'DONE', 'FAILED');

-- CreateEnum
CREATE TYPE "RoundingMode" AS ENUM ('NONE', 'NEAREST_1');

-- CreateEnum
CREATE TYPE "DayCloseKind" AS ENUM ('X', 'Z');

-- AlterEnum (values are used only from the next migration onwards)
ALTER TYPE "OrderStatus" ADD VALUE 'OPEN';
ALTER TYPE "OrderStatus" ADD VALUE 'SENT';
ALTER TYPE "OrderStatus" ADD VALUE 'BILLED';
ALTER TYPE "OrderStatus" ADD VALUE 'CLOSED';
ALTER TYPE "OrderStatus" ADD VALUE 'VOID';

-- CreateTable
CREATE TABLE "tax_classes" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "rate" DECIMAL(5,2) NOT NULL,
    "components" JSONB NOT NULL,
    "inclusive" BOOLEAN NOT NULL DEFAULT false,
    "isLiquor" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "tax_classes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "categories" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "station" TEXT NOT NULL DEFAULT 'KITCHEN',
    "ticketKind" "TicketKind" NOT NULL DEFAULT 'KOT',
    "taxClassId" TEXT,
    "color" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "categories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product_variants" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "price" DECIMAL(12,2) NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "product_variants_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "modifier_groups" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "minSelect" INTEGER NOT NULL DEFAULT 0,
    "maxSelect" INTEGER NOT NULL DEFAULT 1,
    "showOn" TEXT[] DEFAULT ARRAY['POS']::TEXT[],
    "isActive" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "modifier_groups_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "modifier_options" (
    "id" TEXT NOT NULL,
    "groupId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "priceDelta" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "modifier_options_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product_modifier_groups" (
    "productId" TEXT NOT NULL,
    "groupId" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "product_modifier_groups_pkey" PRIMARY KEY ("productId", "groupId")
);

-- CreateTable
CREATE TABLE "combos" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "price" DECIMAL(12,2) NOT NULL,
    "taxClassId" TEXT,
    "days" INTEGER[] DEFAULT ARRAY[0,1,2,3,4,5,6]::INTEGER[],
    "startTime" TEXT,
    "endTime" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "combos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "combo_items" (
    "id" TEXT NOT NULL,
    "comboId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "variantId" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "swapAllowed" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "combo_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "price_rules" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT,
    "name" TEXT NOT NULL,
    "percentOff" DECIMAL(5,2) NOT NULL,
    "categoryIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "productIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "days" INTEGER[] DEFAULT ARRAY[0,1,2,3,4,5,6]::INTEGER[],
    "startTime" TEXT NOT NULL,
    "endTime" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "price_rules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "areas" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "priceMarkupPercent" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "isSmoking" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "areas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "dining_tables" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "areaId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "seats" INTEGER NOT NULL DEFAULT 4,
    "shape" "TableShape" NOT NULL DEFAULT 'SQUARE',
    "posX" INTEGER NOT NULL DEFAULT 0,
    "posY" INTEGER NOT NULL DEFAULT 0,
    "status" "TableStatus" NOT NULL DEFAULT 'FREE',
    "mergedIntoId" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "dining_tables_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "outlet_settings" (
    "outletId" TEXT NOT NULL,
    "serviceChargePercent" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "serviceChargeTypes" "OrderType"[] DEFAULT ARRAY['DINE_IN']::"OrderType"[],
    "roundingMode" "RoundingMode" NOT NULL DEFAULT 'NEAREST_1',
    "orderPrefix" TEXT NOT NULL DEFAULT 'A',
    "lastOrderSeq" INTEGER NOT NULL DEFAULT 0,
    "invoicePrefix" TEXT NOT NULL DEFAULT 'INV',
    "countryCode" TEXT NOT NULL DEFAULT 'IN',
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "outlet_settings_pkey" PRIMARY KEY ("outletId")
);

-- CreateTable
CREATE TABLE "order_discounts" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "type" "DiscountType" NOT NULL,
    "value" DECIMAL(12,2) NOT NULL,
    "itemIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "amount" DECIMAL(12,2) NOT NULL,
    "reason" TEXT NOT NULL,
    "createdById" TEXT NOT NULL,
    "approvedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "order_discounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tickets" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "kind" "TicketKind" NOT NULL,
    "station" TEXT NOT NULL,
    "seq" INTEGER NOT NULL,
    "status" "TicketStatus" NOT NULL DEFAULT 'QUEUED',
    "isCancellation" BOOLEAN NOT NULL DEFAULT false,
    "items" JSONB NOT NULL,
    "printerId" TEXT,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "printedAt" TIMESTAMP(3),

    CONSTRAINT "tickets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "printers" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "connection" "PrinterConnection" NOT NULL DEFAULT 'LAN',
    "host" TEXT,
    "port" INTEGER NOT NULL DEFAULT 9100,
    "paperWidth" INTEGER NOT NULL DEFAULT 80,
    "copies" INTEGER NOT NULL DEFAULT 1,
    "language" TEXT NOT NULL DEFAULT 'en',
    "isReceipt" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "lastStatus" TEXT,
    "lastSeenAt" TIMESTAMP(3),

    CONSTRAINT "printers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "station_routes" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "station" TEXT NOT NULL,
    "printerId" TEXT,
    "fallbackPrinterId" TEXT,

    CONSTRAINT "station_routes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print_jobs" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "printerId" TEXT NOT NULL,
    "kind" "PrintJobKind" NOT NULL,
    "payload" JSONB NOT NULL,
    "status" "PrintJobStatus" NOT NULL DEFAULT 'QUEUED',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "error" TEXT,
    "ticketId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "doneAt" TIMESTAMP(3),

    CONSTRAINT "print_jobs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "approvals" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "orderId" TEXT,
    "type" "ApprovalType" NOT NULL,
    "status" "ApprovalStatus" NOT NULL DEFAULT 'PENDING',
    "requestedById" TEXT NOT NULL,
    "approverId" TEXT,
    "payload" JSONB NOT NULL,
    "reason" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedAt" TIMESTAMP(3),
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),

    CONSTRAINT "approvals_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "day_closes" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "kind" "DayCloseKind" NOT NULL,
    "businessDate" DATE NOT NULL,
    "totals" JSONB NOT NULL,
    "cashCounted" DECIMAL(12,2),
    "cashExpected" DECIMAL(12,2),
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "day_closes_pkey" PRIMARY KEY ("id")
);

-- AlterTable: products
ALTER TABLE "products" ADD COLUMN "categoryId" TEXT,
ADD COLUMN "taxClassId" TEXT,
ADD COLUMN "is86" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "sortOrder" INTEGER NOT NULL DEFAULT 0;

-- AlterTable: orders (status default is changed in the next migration)
ALTER TABLE "orders" ADD COLUMN "orderNumber" TEXT,
ADD COLUMN "type" "OrderType" NOT NULL DEFAULT 'DINE_IN',
ADD COLUMN "tableId" TEXT,
ADD COLUMN "covers" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN "waiterId" TEXT,
ADD COLUMN "discountTotal" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN "serviceCharge" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN "tipTotal" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN "roundOff" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN "taxBreakdown" JSONB,
ADD COLUMN "note" TEXT,
ADD COLUMN "offlineId" TEXT,
ADD COLUMN "heldAt" TIMESTAMP(3),
ADD COLUMN "billedAt" TIMESTAMP(3),
ADD COLUMN "paidAt" TIMESTAMP(3),
ADD COLUMN "closedAt" TIMESTAMP(3),
ADD COLUMN "voidedAt" TIMESTAMP(3),
ADD COLUMN "voidReason" TEXT,
ADD COLUMN "dayCloseId" TEXT,
ALTER COLUMN "invoiceNumber" DROP NOT NULL;

-- Existing orders came from the legacy billing screen, which is takeaway (PLAN.md 1.5)
UPDATE "orders" SET "type" = 'TAKEAWAY';

-- AlterTable: order_items
ALTER TABLE "order_items" ADD COLUMN "variantId" TEXT,
ADD COLUMN "variantName" TEXT,
ADD COLUMN "seat" INTEGER,
ADD COLUMN "status" "OrderItemStatus" NOT NULL DEFAULT 'NEW',
ADD COLUMN "modifiers" JSONB NOT NULL DEFAULT '[]',
ADD COLUMN "note" TEXT,
ADD COLUMN "grossAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN "discountAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN "happyHourPercent" DECIMAL(5,2),
ADD COLUMN "taxClassId" TEXT,
ADD COLUMN "taxBreakdown" JSONB,
ADD COLUMN "comboId" TEXT,
ADD COLUMN "sentAt" TIMESTAMP(3),
ADD COLUMN "voidedAt" TIMESTAMP(3),
ADD COLUMN "voidReason" TEXT,
ADD COLUMN "createdById" TEXT,
ALTER COLUMN "productId" DROP NOT NULL;

-- Legacy lines are finished lines: gross is price x quantity (ex-tax, no discount)
UPDATE "order_items" SET "grossAmount" = ROUND("price" * "quantity", 2), "status" = 'SENT';

-- AlterTable: payments
ALTER TABLE "payments" ADD COLUMN "seat" INTEGER,
ADD COLUMN "tipAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN "tendered" DECIMAL(12,2),
ADD COLUMN "changeGiven" DECIMAL(12,2),
ADD COLUMN "reference" TEXT,
ADD COLUMN "createdById" TEXT;

-- Default tax classes for every tenant (PLAN.md Phase 2 P2-A step 2)
INSERT INTO "tax_classes" ("id", "tenantId", "name", "code", "rate", "components", "inclusive", "isLiquor", "isActive", "createdAt", "updatedAt")
SELECT gen_random_uuid()::text, t."id", 'GST 5% (restaurant)', 'GST5', 5.00,
  '[{"name":"CGST","rate":2.5},{"name":"SGST","rate":2.5}]'::jsonb, false, false, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "tenants" t;

INSERT INTO "tax_classes" ("id", "tenantId", "name", "code", "rate", "components", "inclusive", "isLiquor", "isActive", "createdAt", "updatedAt")
SELECT gen_random_uuid()::text, t."id", 'VAT 20% (liquor)', 'VAT_LIQUOR', 20.00,
  '[{"name":"VAT","rate":20}]'::jsonb, false, true, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "tenants" t;

INSERT INTO "tax_classes" ("id", "tenantId", "name", "code", "rate", "components", "inclusive", "isLiquor", "isActive", "createdAt", "updatedAt")
SELECT gen_random_uuid()::text, t."id", 'GST 18%', 'GST18', 18.00,
  '[{"name":"CGST","rate":9},{"name":"SGST","rate":9}]'::jsonb, false, false, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "tenants" t;

-- Outlet settings row for every existing outlet (service charge stays 0 until an admin sets it)
INSERT INTO "outlet_settings" ("outletId", "serviceChargePercent", "serviceChargeTypes", "roundingMode", "orderPrefix", "lastOrderSeq", "invoicePrefix", "countryCode", "updatedAt")
SELECT o."id", 0, ARRAY['DINE_IN']::"OrderType"[], 'NEAREST_1', 'A', 0, 'INV', 'IN', CURRENT_TIMESTAMP
FROM "outlets" o
ON CONFLICT ("outletId") DO NOTHING;

-- CreateIndex
CREATE UNIQUE INDEX "tax_classes_tenantId_code_key" ON "tax_classes"("tenantId", "code");

-- CreateIndex
CREATE INDEX "categories_tenantId_idx" ON "categories"("tenantId");

-- CreateIndex
CREATE INDEX "product_variants_productId_idx" ON "product_variants"("productId");

-- CreateIndex
CREATE INDEX "modifier_groups_tenantId_idx" ON "modifier_groups"("tenantId");

-- CreateIndex
CREATE INDEX "modifier_options_groupId_idx" ON "modifier_options"("groupId");

-- CreateIndex
CREATE INDEX "product_modifier_groups_groupId_idx" ON "product_modifier_groups"("groupId");

-- CreateIndex
CREATE INDEX "combos_tenantId_idx" ON "combos"("tenantId");

-- CreateIndex
CREATE INDEX "combo_items_comboId_idx" ON "combo_items"("comboId");

-- CreateIndex
CREATE INDEX "price_rules_tenantId_idx" ON "price_rules"("tenantId");

-- CreateIndex
CREATE INDEX "areas_outletId_idx" ON "areas"("outletId");

-- CreateIndex
CREATE UNIQUE INDEX "dining_tables_outletId_name_key" ON "dining_tables"("outletId", "name");

-- CreateIndex
CREATE INDEX "dining_tables_outletId_idx" ON "dining_tables"("outletId");

-- CreateIndex
CREATE INDEX "order_discounts_orderId_idx" ON "order_discounts"("orderId");

-- CreateIndex
CREATE INDEX "tickets_outletId_createdAt_idx" ON "tickets"("outletId", "createdAt");

-- CreateIndex
CREATE INDEX "tickets_orderId_idx" ON "tickets"("orderId");

-- CreateIndex
CREATE INDEX "printers_outletId_idx" ON "printers"("outletId");

-- CreateIndex
CREATE UNIQUE INDEX "station_routes_outletId_station_key" ON "station_routes"("outletId", "station");

-- CreateIndex
CREATE INDEX "print_jobs_outletId_status_idx" ON "print_jobs"("outletId", "status");

-- CreateIndex
CREATE INDEX "approvals_outletId_status_idx" ON "approvals"("outletId", "status");

-- CreateIndex
CREATE INDEX "approvals_orderId_idx" ON "approvals"("orderId");

-- CreateIndex
CREATE INDEX "day_closes_outletId_businessDate_idx" ON "day_closes"("outletId", "businessDate");

-- CreateIndex
CREATE INDEX "products_categoryId_idx" ON "products"("categoryId");

-- CreateIndex
CREATE UNIQUE INDEX "orders_outletId_orderNumber_key" ON "orders"("outletId", "orderNumber");

-- CreateIndex
CREATE UNIQUE INDEX "orders_offlineId_key" ON "orders"("offlineId");

-- CreateIndex
CREATE INDEX "orders_outletId_status_idx" ON "orders"("outletId", "status");

-- CreateIndex
CREATE INDEX "orders_tableId_idx" ON "orders"("tableId");

-- CreateIndex
CREATE INDEX "orders_dayCloseId_idx" ON "orders"("dayCloseId");

-- AddForeignKey
ALTER TABLE "tax_classes" ADD CONSTRAINT "tax_classes_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "categories" ADD CONSTRAINT "categories_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "categories" ADD CONSTRAINT "categories_taxClassId_fkey" FOREIGN KEY ("taxClassId") REFERENCES "tax_classes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_taxClassId_fkey" FOREIGN KEY ("taxClassId") REFERENCES "tax_classes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_variants" ADD CONSTRAINT "product_variants_productId_fkey" FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "modifier_groups" ADD CONSTRAINT "modifier_groups_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "modifier_options" ADD CONSTRAINT "modifier_options_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "modifier_groups"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_modifier_groups" ADD CONSTRAINT "product_modifier_groups_productId_fkey" FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_modifier_groups" ADD CONSTRAINT "product_modifier_groups_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "modifier_groups"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "combos" ADD CONSTRAINT "combos_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "combos" ADD CONSTRAINT "combos_taxClassId_fkey" FOREIGN KEY ("taxClassId") REFERENCES "tax_classes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "combo_items" ADD CONSTRAINT "combo_items_comboId_fkey" FOREIGN KEY ("comboId") REFERENCES "combos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "combo_items" ADD CONSTRAINT "combo_items_productId_fkey" FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "price_rules" ADD CONSTRAINT "price_rules_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "price_rules" ADD CONSTRAINT "price_rules_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "areas" ADD CONSTRAINT "areas_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "areas" ADD CONSTRAINT "areas_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dining_tables" ADD CONSTRAINT "dining_tables_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dining_tables" ADD CONSTRAINT "dining_tables_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dining_tables" ADD CONSTRAINT "dining_tables_areaId_fkey" FOREIGN KEY ("areaId") REFERENCES "areas"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "outlet_settings" ADD CONSTRAINT "outlet_settings_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_tableId_fkey" FOREIGN KEY ("tableId") REFERENCES "dining_tables"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_waiterId_fkey" FOREIGN KEY ("waiterId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_dayCloseId_fkey" FOREIGN KEY ("dayCloseId") REFERENCES "day_closes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_items" ADD CONSTRAINT "order_items_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_discounts" ADD CONSTRAINT "order_discounts_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_discounts" ADD CONSTRAINT "order_discounts_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_discounts" ADD CONSTRAINT "order_discounts_approvedById_fkey" FOREIGN KEY ("approvedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tickets" ADD CONSTRAINT "tickets_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tickets" ADD CONSTRAINT "tickets_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tickets" ADD CONSTRAINT "tickets_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tickets" ADD CONSTRAINT "tickets_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "printers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tickets" ADD CONSTRAINT "tickets_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "printers" ADD CONSTRAINT "printers_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "printers" ADD CONSTRAINT "printers_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "station_routes" ADD CONSTRAINT "station_routes_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "station_routes" ADD CONSTRAINT "station_routes_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "station_routes" ADD CONSTRAINT "station_routes_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "printers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "station_routes" ADD CONSTRAINT "station_routes_fallbackPrinterId_fkey" FOREIGN KEY ("fallbackPrinterId") REFERENCES "printers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "printers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_ticketId_fkey" FOREIGN KEY ("ticketId") REFERENCES "tickets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "approvals" ADD CONSTRAINT "approvals_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "approvals" ADD CONSTRAINT "approvals_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "approvals" ADD CONSTRAINT "approvals_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "approvals" ADD CONSTRAINT "approvals_requestedById_fkey" FOREIGN KEY ("requestedById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "approvals" ADD CONSTRAINT "approvals_approverId_fkey" FOREIGN KEY ("approverId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "day_closes" ADD CONSTRAINT "day_closes_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "day_closes" ADD CONSTRAINT "day_closes_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "day_closes" ADD CONSTRAINT "day_closes_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Order lines keep their entry order.
ALTER TABLE "order_items" ADD COLUMN "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
