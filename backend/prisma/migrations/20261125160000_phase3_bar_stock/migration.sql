-- Phase 3 bar operations, KDS and stock: stock items, locations, levels and the movement ledger,
-- recipes, transfers, counts, wastage, vendors, purchase orders, goods receipts, debit notes,
-- bar tabs, bottle locker, KDS ticket status, the kds.bump permission and default stock locations.

-- CreateEnum
CREATE TYPE "StockUnit" AS ENUM ('ML', 'G', 'PC');

-- CreateEnum
CREATE TYPE "CostingMethod" AS ENUM ('WEIGHTED_AVERAGE', 'FIFO');

-- CreateEnum
CREATE TYPE "StockLocationKind" AS ENUM ('STORE', 'BAR', 'KITCHEN', 'CELLAR');

-- CreateEnum
CREATE TYPE "StockMovementType" AS ENUM ('OPENING', 'RECEIPT', 'SALE', 'SALE_REVERSAL', 'WASTAGE', 'TRANSFER_OUT', 'TRANSFER_IN', 'COUNT_ADJUST');

-- CreateEnum
CREATE TYPE "WastageReason" AS ENUM ('BROKEN', 'SPILLED', 'EXPIRED', 'COMP', 'STAFF_MEAL', 'BURNT', 'DROPPED', 'RETURNED', 'DAMAGED_DELIVERY', 'VOID', 'OTHER');

-- CreateEnum
CREATE TYPE "StockCountStatus" AS ENUM ('OPEN', 'SUBMITTED', 'POSTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "PurchaseOrderStatus" AS ENUM ('DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'SENT', 'PARTLY_RECEIVED', 'RECEIVED', 'INVOICE_MISMATCH', 'CANCELLED');

-- CreateEnum
CREATE TYPE "GrnStatus" AS ENUM ('DRAFT', 'POSTED');

-- CreateEnum
CREATE TYPE "DebitNoteStatus" AS ENUM ('OPEN', 'SETTLED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "TabStatus" AS ENUM ('OPEN', 'CLOSED', 'VOID');

-- CreateEnum
CREATE TYPE "TabSecurity" AS ENUM ('CARD_PREAUTH', 'CASH_DEPOSIT', 'HOUSE_ACCOUNT', 'NONE');

-- CreateEnum
CREATE TYPE "TabLinkType" AS ENUM ('BAR_SEAT', 'TABLE', 'QUEUE_TOKEN', 'NONE');

-- CreateEnum
CREATE TYPE "LockerStatus" AS ENUM ('ACTIVE', 'FINISHED', 'EXPIRED', 'REMOVED');

-- CreateEnum
CREATE TYPE "LockerEventKind" AS ENUM ('STORE', 'SERVE', 'ADJUST', 'REMOVE');

-- CreateEnum
CREATE TYPE "KdsStatus" AS ENUM ('NEW', 'PREPARING', 'READY', 'SERVED');

-- AlterEnum (value is not used elsewhere in this migration)
ALTER TYPE "ApprovalType" ADD VALUE 'TAB_NO_SECURITY';

-- CreateTable
CREATE TABLE "stock_items" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "sku" TEXT,
    "categoryName" TEXT,
    "baseUnit" "StockUnit" NOT NULL DEFAULT 'ML',
    "packSize" DECIMAL(14,3) NOT NULL DEFAULT 1,
    "packName" TEXT NOT NULL DEFAULT 'pc',
    "purchaseUnitName" TEXT NOT NULL DEFAULT 'Unit',
    "purchaseUnitQty" DECIMAL(14,3) NOT NULL DEFAULT 1,
    "costingMethod" "CostingMethod" NOT NULL DEFAULT 'WEIGHTED_AVERAGE',
    "avgCost" DECIMAL(14,6) NOT NULL DEFAULT 0,
    "lastPurchaseRate" DECIMAL(12,2),
    "preferredVendorId" TEXT,
    "isLiquor" BOOLEAN NOT NULL DEFAULT false,
    "isKeg" BOOLEAN NOT NULL DEFAULT false,
    "shelfLifeDays" INTEGER,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "stock_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_locations" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "kind" "StockLocationKind" NOT NULL,
    "stations" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "isDefaultSales" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "stock_locations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_levels" (
    "locationId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "onHand" DECIMAL(14,3) NOT NULL DEFAULT 0,
    "parLevel" DECIMAL(14,3) NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "stock_levels_pkey" PRIMARY KEY ("locationId", "stockItemId")
);

-- CreateTable
CREATE TABLE "stock_movements" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "locationId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "type" "StockMovementType" NOT NULL,
    "qty" DECIMAL(14,3) NOT NULL,
    "unitCost" DECIMAL(14,6) NOT NULL,
    "refType" TEXT,
    "refId" TEXT,
    "businessDate" DATE NOT NULL,
    "note" TEXT,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "stock_movements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "recipes" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "variantId" TEXT,
    "note" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "recipes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "recipe_lines" (
    "id" TEXT NOT NULL,
    "recipeId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "qty" DECIMAL(14,3) NOT NULL,
    "wastagePercent" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "recipe_lines_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_transfers" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "number" TEXT NOT NULL,
    "fromLocationId" TEXT NOT NULL,
    "toLocationId" TEXT NOT NULL,
    "note" TEXT,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "stock_transfers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_transfer_lines" (
    "id" TEXT NOT NULL,
    "transferId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "qty" DECIMAL(14,3) NOT NULL,

    CONSTRAINT "stock_transfer_lines_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_counts" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "locationId" TEXT NOT NULL,
    "status" "StockCountStatus" NOT NULL DEFAULT 'OPEN',
    "businessDate" DATE NOT NULL,
    "startedById" TEXT NOT NULL,
    "submittedAt" TIMESTAMP(3),
    "postedAt" TIMESTAMP(3),
    "postedById" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "stock_counts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_count_lines" (
    "id" TEXT NOT NULL,
    "countId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "countedQty" DECIMAL(14,3),
    "expectedQty" DECIMAL(14,3),
    "note" TEXT,
    "confirmedOutlier" BOOLEAN NOT NULL DEFAULT false,
    "countedAt" TIMESTAMP(3),
    "countedById" TEXT,

    CONSTRAINT "stock_count_lines_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "wastage_entries" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "locationId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "qty" DECIMAL(14,3) NOT NULL,
    "value" DECIMAL(12,2) NOT NULL,
    "reason" "WastageReason" NOT NULL,
    "note" TEXT,
    "photoUrl" TEXT,
    "refType" TEXT,
    "refId" TEXT,
    "businessDate" DATE NOT NULL,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "wastage_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "vendors" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "contactName" TEXT,
    "phone" TEXT,
    "email" TEXT,
    "gstin" TEXT,
    "address" TEXT,
    "paymentTermsDays" INTEGER NOT NULL DEFAULT 30,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "vendors_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_orders" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "number" TEXT NOT NULL,
    "vendorId" TEXT NOT NULL,
    "locationId" TEXT NOT NULL,
    "status" "PurchaseOrderStatus" NOT NULL DEFAULT 'DRAFT',
    "dueDate" DATE,
    "transportPermitNo" TEXT,
    "total" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "note" TEXT,
    "createdById" TEXT NOT NULL,
    "submittedAt" TIMESTAMP(3),
    "approvedById" TEXT,
    "approvedAt" TIMESTAMP(3),
    "sentAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "purchase_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_order_lines" (
    "id" TEXT NOT NULL,
    "poId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "qty" DECIMAL(12,3) NOT NULL,
    "rate" DECIMAL(12,2) NOT NULL,
    "total" DECIMAL(12,2) NOT NULL,
    "receivedQty" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "purchase_order_lines_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "goods_receipts" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "number" TEXT NOT NULL,
    "poId" TEXT,
    "vendorId" TEXT NOT NULL,
    "locationId" TEXT NOT NULL,
    "status" "GrnStatus" NOT NULL DEFAULT 'DRAFT',
    "vendorInvoiceNo" TEXT,
    "invoiceDate" DATE,
    "receivedOn" DATE NOT NULL,
    "transportPermitNo" TEXT,
    "invoicePhotoUrl" TEXT,
    "poValue" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "invoiceValue" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "receivedValue" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "debitNoteAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "damagedValue" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "payable" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "mismatch" BOOLEAN NOT NULL DEFAULT false,
    "createdById" TEXT NOT NULL,
    "postedById" TEXT,
    "postedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "goods_receipts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "goods_receipt_lines" (
    "id" TEXT NOT NULL,
    "grnId" TEXT NOT NULL,
    "poLineId" TEXT,
    "stockItemId" TEXT NOT NULL,
    "orderedQty" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "invoicedQty" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "receivedQty" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "damagedQty" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "rate" DECIMAL(12,2) NOT NULL,
    "batch" TEXT,
    "expiry" DATE,

    CONSTRAINT "goods_receipt_lines_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "debit_notes" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "number" TEXT NOT NULL,
    "vendorId" TEXT NOT NULL,
    "grnId" TEXT,
    "amount" DECIMAL(12,2) NOT NULL,
    "reason" TEXT NOT NULL,
    "status" "DebitNoteStatus" NOT NULL DEFAULT 'OPEN',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "debit_notes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "document_counters" (
    "tenantId" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "value" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "document_counters_pkey" PRIMARY KEY ("tenantId", "key")
);

-- CreateTable
CREATE TABLE "bar_tabs" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "number" TEXT NOT NULL,
    "businessDate" DATE NOT NULL,
    "orderId" TEXT NOT NULL,
    "guestName" TEXT NOT NULL,
    "mobile" TEXT,
    "ageChecked" BOOLEAN NOT NULL,
    "security" "TabSecurity" NOT NULL,
    "cardLast4" TEXT,
    "amountHeld" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "houseAccount" TEXT,
    "tabLimit" DECIMAL(12,2) NOT NULL,
    "warnAtPercent" INTEGER NOT NULL DEFAULT 80,
    "warnedAt" TIMESTAMP(3),
    "linkType" "TabLinkType" NOT NULL DEFAULT 'NONE',
    "linkLabel" TEXT,
    "tableId" TEXT,
    "status" "TabStatus" NOT NULL DEFAULT 'OPEN',
    "approvalId" TEXT,
    "openedById" TEXT NOT NULL,
    "openedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "closedAt" TIMESTAMP(3),
    "closedById" TEXT,

    CONSTRAINT "bar_tabs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bottle_locker_entries" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "guestName" TEXT NOT NULL,
    "mobile" TEXT,
    "cardLast4" TEXT,
    "stockItemId" TEXT,
    "bottleName" TEXT NOT NULL,
    "bottleMl" INTEGER NOT NULL,
    "remainingMl" INTEGER NOT NULL,
    "storedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" DATE NOT NULL,
    "status" "LockerStatus" NOT NULL DEFAULT 'ACTIVE',
    "orderItemId" TEXT,
    "note" TEXT,
    "createdById" TEXT NOT NULL,

    CONSTRAINT "bottle_locker_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bottle_locker_events" (
    "id" TEXT NOT NULL,
    "entryId" TEXT NOT NULL,
    "kind" "LockerEventKind" NOT NULL,
    "ml" INTEGER NOT NULL,
    "byId" TEXT NOT NULL,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "bottle_locker_events_pkey" PRIMARY KEY ("id")
);

-- AlterTable: products
ALTER TABLE "products" ADD COLUMN "auto86" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable: modifier_options
ALTER TABLE "modifier_options" ADD COLUMN "stockItemId" TEXT,
ADD COLUMN "stockQty" DECIMAL(14,3);

-- AlterTable: tickets (KDS status; existing Phase 2 tickets are marked served below)
ALTER TABLE "tickets" ADD COLUMN "kdsStatus" "KdsStatus" NOT NULL DEFAULT 'NEW',
ADD COLUMN "startedAt" TIMESTAMP(3),
ADD COLUMN "readyAt" TIMESTAMP(3),
ADD COLUMN "servedAt" TIMESTAMP(3),
ADD COLUMN "recalledAt" TIMESTAMP(3),
ADD COLUMN "bumpedById" TEXT,
ADD COLUMN "overdueAlertedAt" TIMESTAMP(3);

-- Old Phase 2 tickets must not flood the KDS
UPDATE "tickets" SET "kdsStatus" = 'SERVED' WHERE "createdAt" < now();

-- Permission kds.bump (PLAN.md 1.6): sits right after sales.tab.open (sortOrder 5)
UPDATE "permissions" SET "sortOrder" = "sortOrder" + 1 WHERE "sortOrder" >= 6;

INSERT INTO "permissions" ("key", "group", "label", "description", "limitUnit", "sortOrder") VALUES
  ('kds.bump', 'Sales', 'Kitchen display (start, bump, recall)', NULL, NULL, 6);

-- Default matrix for kds.bump. Only non-NONE grants are stored; storekeeper and kiosk stay NONE.
INSERT INTO "persona_permissions" ("personaId", "permissionKey", "level", "limitValue")
SELECT p."id", v."permissionKey", v."level"::"AccessLevel", NULL::DECIMAL(12,2)
FROM "personas" p
JOIN (VALUES
  ('admin', 'kds.bump', 'EDIT'),
  ('manager', 'kds.bump', 'EDIT'),
  ('bartender', 'kds.bump', 'EDIT'),
  ('chef', 'kds.bump', 'EDIT'),
  ('captain', 'kds.bump', 'VIEW'),
  ('waiter', 'kds.bump', 'VIEW'),
  ('cashier', 'kds.bump', 'VIEW')
) AS v("personaKey", "permissionKey", "level") ON v."personaKey" = p."key";

-- Default stock locations for every existing outlet (PLAN.md 1.5)
INSERT INTO "stock_locations" ("id", "tenantId", "outletId", "name", "kind", "stations", "isDefaultSales", "isActive", "sortOrder")
SELECT gen_random_uuid()::text, o."tenantId", o."id", v."name", v."kind"::"StockLocationKind", v."stations"::TEXT[], v."isDefaultSales", true, v."sortOrder"
FROM "outlets" o
CROSS JOIN (VALUES
  ('Main store', 'STORE', '{}', false, 0),
  ('Bar', 'BAR', '{BAR}', false, 1),
  ('Kitchen', 'KITCHEN', '{KITCHEN,TANDOOR,GRILL}', true, 2),
  ('Cellar', 'CELLAR', '{}', false, 3)
) AS v("name", "kind", "stations", "isDefaultSales", "sortOrder");

-- CreateIndex
CREATE UNIQUE INDEX "stock_items_tenantId_name_key" ON "stock_items"("tenantId", "name");

-- CreateIndex
CREATE INDEX "stock_items_tenantId_idx" ON "stock_items"("tenantId");

-- CreateIndex
CREATE UNIQUE INDEX "stock_locations_outletId_name_key" ON "stock_locations"("outletId", "name");

-- CreateIndex
CREATE INDEX "stock_locations_outletId_idx" ON "stock_locations"("outletId");

-- CreateIndex
CREATE INDEX "stock_movements_locationId_stockItemId_businessDate_idx" ON "stock_movements"("locationId", "stockItemId", "businessDate");

-- CreateIndex
CREATE INDEX "stock_movements_refType_refId_idx" ON "stock_movements"("refType", "refId");

-- CreateIndex
CREATE INDEX "stock_movements_outletId_businessDate_idx" ON "stock_movements"("outletId", "businessDate");

-- CreateIndex
CREATE UNIQUE INDEX "recipes_productId_variantId_key" ON "recipes"("productId", "variantId");

-- CreateIndex
CREATE INDEX "recipe_lines_recipeId_idx" ON "recipe_lines"("recipeId");

-- CreateIndex
CREATE UNIQUE INDEX "stock_transfers_tenantId_number_key" ON "stock_transfers"("tenantId", "number");

-- CreateIndex
CREATE INDEX "stock_transfers_outletId_createdAt_idx" ON "stock_transfers"("outletId", "createdAt");

-- CreateIndex
CREATE INDEX "stock_counts_outletId_status_idx" ON "stock_counts"("outletId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "stock_count_lines_countId_stockItemId_key" ON "stock_count_lines"("countId", "stockItemId");

-- CreateIndex
CREATE INDEX "wastage_entries_outletId_businessDate_idx" ON "wastage_entries"("outletId", "businessDate");

-- CreateIndex
CREATE UNIQUE INDEX "vendors_tenantId_name_key" ON "vendors"("tenantId", "name");

-- CreateIndex
CREATE UNIQUE INDEX "purchase_orders_tenantId_number_key" ON "purchase_orders"("tenantId", "number");

-- CreateIndex
CREATE INDEX "purchase_orders_outletId_status_idx" ON "purchase_orders"("outletId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "goods_receipts_tenantId_number_key" ON "goods_receipts"("tenantId", "number");

-- CreateIndex
CREATE INDEX "goods_receipts_outletId_createdAt_idx" ON "goods_receipts"("outletId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "debit_notes_tenantId_number_key" ON "debit_notes"("tenantId", "number");

-- CreateIndex
CREATE UNIQUE INDEX "bar_tabs_orderId_key" ON "bar_tabs"("orderId");

-- CreateIndex
CREATE INDEX "bar_tabs_outletId_status_idx" ON "bar_tabs"("outletId", "status");

-- CreateIndex
CREATE INDEX "bottle_locker_entries_outletId_status_idx" ON "bottle_locker_entries"("outletId", "status");

-- CreateIndex
CREATE INDEX "tickets_outletId_kdsStatus_idx" ON "tickets"("outletId", "kdsStatus");

-- AddForeignKey
ALTER TABLE "stock_items" ADD CONSTRAINT "stock_items_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_items" ADD CONSTRAINT "stock_items_preferredVendorId_fkey" FOREIGN KEY ("preferredVendorId") REFERENCES "vendors"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_locations" ADD CONSTRAINT "stock_locations_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_locations" ADD CONSTRAINT "stock_locations_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_levels" ADD CONSTRAINT "stock_levels_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "stock_locations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_levels" ADD CONSTRAINT "stock_levels_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_movements" ADD CONSTRAINT "stock_movements_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_movements" ADD CONSTRAINT "stock_movements_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_movements" ADD CONSTRAINT "stock_movements_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "stock_locations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_movements" ADD CONSTRAINT "stock_movements_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_movements" ADD CONSTRAINT "stock_movements_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recipes" ADD CONSTRAINT "recipes_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recipes" ADD CONSTRAINT "recipes_productId_fkey" FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recipes" ADD CONSTRAINT "recipes_variantId_fkey" FOREIGN KEY ("variantId") REFERENCES "product_variants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recipe_lines" ADD CONSTRAINT "recipe_lines_recipeId_fkey" FOREIGN KEY ("recipeId") REFERENCES "recipes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recipe_lines" ADD CONSTRAINT "recipe_lines_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "modifier_options" ADD CONSTRAINT "modifier_options_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_transfers" ADD CONSTRAINT "stock_transfers_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_transfers" ADD CONSTRAINT "stock_transfers_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_transfers" ADD CONSTRAINT "stock_transfers_fromLocationId_fkey" FOREIGN KEY ("fromLocationId") REFERENCES "stock_locations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_transfers" ADD CONSTRAINT "stock_transfers_toLocationId_fkey" FOREIGN KEY ("toLocationId") REFERENCES "stock_locations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_transfers" ADD CONSTRAINT "stock_transfers_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_transfer_lines" ADD CONSTRAINT "stock_transfer_lines_transferId_fkey" FOREIGN KEY ("transferId") REFERENCES "stock_transfers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_transfer_lines" ADD CONSTRAINT "stock_transfer_lines_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_counts" ADD CONSTRAINT "stock_counts_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_counts" ADD CONSTRAINT "stock_counts_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_counts" ADD CONSTRAINT "stock_counts_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "stock_locations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_counts" ADD CONSTRAINT "stock_counts_startedById_fkey" FOREIGN KEY ("startedById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_counts" ADD CONSTRAINT "stock_counts_postedById_fkey" FOREIGN KEY ("postedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_count_lines" ADD CONSTRAINT "stock_count_lines_countId_fkey" FOREIGN KEY ("countId") REFERENCES "stock_counts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_count_lines" ADD CONSTRAINT "stock_count_lines_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_count_lines" ADD CONSTRAINT "stock_count_lines_countedById_fkey" FOREIGN KEY ("countedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wastage_entries" ADD CONSTRAINT "wastage_entries_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wastage_entries" ADD CONSTRAINT "wastage_entries_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wastage_entries" ADD CONSTRAINT "wastage_entries_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "stock_locations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wastage_entries" ADD CONSTRAINT "wastage_entries_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wastage_entries" ADD CONSTRAINT "wastage_entries_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vendors" ADD CONSTRAINT "vendors_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_vendorId_fkey" FOREIGN KEY ("vendorId") REFERENCES "vendors"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "stock_locations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_approvedById_fkey" FOREIGN KEY ("approvedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_order_lines" ADD CONSTRAINT "purchase_order_lines_poId_fkey" FOREIGN KEY ("poId") REFERENCES "purchase_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_order_lines" ADD CONSTRAINT "purchase_order_lines_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipts" ADD CONSTRAINT "goods_receipts_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipts" ADD CONSTRAINT "goods_receipts_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipts" ADD CONSTRAINT "goods_receipts_poId_fkey" FOREIGN KEY ("poId") REFERENCES "purchase_orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipts" ADD CONSTRAINT "goods_receipts_vendorId_fkey" FOREIGN KEY ("vendorId") REFERENCES "vendors"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipts" ADD CONSTRAINT "goods_receipts_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "stock_locations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipts" ADD CONSTRAINT "goods_receipts_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipts" ADD CONSTRAINT "goods_receipts_postedById_fkey" FOREIGN KEY ("postedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipt_lines" ADD CONSTRAINT "goods_receipt_lines_grnId_fkey" FOREIGN KEY ("grnId") REFERENCES "goods_receipts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipt_lines" ADD CONSTRAINT "goods_receipt_lines_poLineId_fkey" FOREIGN KEY ("poLineId") REFERENCES "purchase_order_lines"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goods_receipt_lines" ADD CONSTRAINT "goods_receipt_lines_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debit_notes" ADD CONSTRAINT "debit_notes_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debit_notes" ADD CONSTRAINT "debit_notes_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debit_notes" ADD CONSTRAINT "debit_notes_vendorId_fkey" FOREIGN KEY ("vendorId") REFERENCES "vendors"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "debit_notes" ADD CONSTRAINT "debit_notes_grnId_fkey" FOREIGN KEY ("grnId") REFERENCES "goods_receipts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "document_counters" ADD CONSTRAINT "document_counters_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bar_tabs" ADD CONSTRAINT "bar_tabs_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bar_tabs" ADD CONSTRAINT "bar_tabs_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bar_tabs" ADD CONSTRAINT "bar_tabs_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bar_tabs" ADD CONSTRAINT "bar_tabs_tableId_fkey" FOREIGN KEY ("tableId") REFERENCES "dining_tables"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bar_tabs" ADD CONSTRAINT "bar_tabs_openedById_fkey" FOREIGN KEY ("openedById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bar_tabs" ADD CONSTRAINT "bar_tabs_closedById_fkey" FOREIGN KEY ("closedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bottle_locker_entries" ADD CONSTRAINT "bottle_locker_entries_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bottle_locker_entries" ADD CONSTRAINT "bottle_locker_entries_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "outlets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bottle_locker_entries" ADD CONSTRAINT "bottle_locker_entries_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "stock_items"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bottle_locker_entries" ADD CONSTRAINT "bottle_locker_entries_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bottle_locker_events" ADD CONSTRAINT "bottle_locker_events_entryId_fkey" FOREIGN KEY ("entryId") REFERENCES "bottle_locker_entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bottle_locker_events" ADD CONSTRAINT "bottle_locker_events_byId_fkey" FOREIGN KEY ("byId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tickets" ADD CONSTRAINT "tickets_bumpedById_fkey" FOREIGN KEY ("bumpedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
