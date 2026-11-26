-- Phase 4: guest QR table ordering (docs/phase-4/PLAN.md 2.1, 2.7)

-- CreateEnum
CREATE TYPE "OrderSource" AS ENUM ('POS', 'KIOSK', 'GUEST_QR');

-- CreateEnum
CREATE TYPE "GuestSessionStatus" AS ENUM ('OPEN', 'CLOSED');

-- CreateEnum
CREATE TYPE "GuestRequestStatus" AS ENUM ('PENDING', 'CONFIRMED', 'REJECTED', 'CANCELLED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "ServiceRequestType" AS ENUM ('CALL_WAITER', 'BILL');

-- CreateEnum
CREATE TYPE "ServiceRequestStatus" AS ENUM ('OPEN', 'ACKNOWLEDGED', 'DONE');

-- CreateEnum
CREATE TYPE "GuestVerifyMethod" AS ENUM ('STATIC_OTP', 'TABLE_PIN', 'SMS_OTP');

-- AlterTable
ALTER TABLE "dining_tables" ADD COLUMN     "guestPin" TEXT,
ADD COLUMN     "qrEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "qrToken" TEXT;

-- Backfill: 22-char url-safe random token per existing table (88 bits from two v4 uuids), then require it
UPDATE "dining_tables"
SET "qrToken" = substr(replace(gen_random_uuid()::text || gen_random_uuid()::text, chr(45), ''), 1, 22)
WHERE "qrToken" IS NULL;
ALTER TABLE "dining_tables" ALTER COLUMN "qrToken" SET NOT NULL;
-- New tables get a token from the database default; the app rotates it with a base64url token
ALTER TABLE "dining_tables" ALTER COLUMN "qrToken" SET DEFAULT substr(replace(((gen_random_uuid())::text || (gen_random_uuid())::text), '-'::text, ''::text), 1, 22);

-- AlterTable
ALTER TABLE "order_items" ADD COLUMN     "guestName" TEXT,
ADD COLUMN     "guestRequestId" TEXT;

-- AlterTable
ALTER TABLE "orders" ADD COLUMN     "guestSessionId" TEXT,
ADD COLUMN     "source" "OrderSource" NOT NULL DEFAULT 'POS';

-- CreateTable
CREATE TABLE "guest_configs" (
    "tenantId" TEXT NOT NULL,
    "config" JSONB NOT NULL,
    "updatedById" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "guest_configs_pkey" PRIMARY KEY ("tenantId")
);

-- CreateTable
CREATE TABLE "guest_sessions" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "tableId" TEXT NOT NULL,
    "orderId" TEXT,
    "status" "GuestSessionStatus" NOT NULL DEFAULT 'OPEN',
    "ageConfirmedAt" TIMESTAMP(3),
    "openedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "closedAt" TIMESTAMP(3),

    CONSTRAINT "guest_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guest_participants" (
    "id" TEXT NOT NULL,
    "sessionId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "verifiedAt" TIMESTAMP(3),
    "verifyMethod" "GuestVerifyMethod",
    "consentAt" TIMESTAMP(3) NOT NULL,
    "deviceKey" TEXT NOT NULL,
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "guest_participants_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guest_verifications" (
    "id" TEXT NOT NULL,
    "tableId" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "deviceKey" TEXT NOT NULL,
    "consentAt" TIMESTAMP(3) NOT NULL,
    "method" "GuestVerifyMethod" NOT NULL,
    "codeHash" TEXT,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "lockedUntil" TIMESTAMP(3),
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "verifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "guest_verifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guest_order_requests" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "sessionId" TEXT NOT NULL,
    "participantId" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "roundKey" TEXT NOT NULL,
    "status" "GuestRequestStatus" NOT NULL DEFAULT 'PENDING',
    "items" JSONB NOT NULL,
    "claimedById" TEXT,
    "decidedById" TEXT,
    "decidedAt" TIMESTAMP(3),
    "rejectReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "guest_order_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_requests" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "sessionId" TEXT NOT NULL,
    "tableId" TEXT NOT NULL,
    "type" "ServiceRequestType" NOT NULL,
    "status" "ServiceRequestStatus" NOT NULL DEFAULT 'OPEN',
    "acknowledgedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "doneAt" TIMESTAMP(3),

    CONSTRAINT "service_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "guest_sessions_tableId_status_idx" ON "guest_sessions"("tableId", "status");

-- CreateIndex
CREATE INDEX "guest_sessions_tenantId_idx" ON "guest_sessions"("tenantId");

-- CreateIndex
CREATE INDEX "guest_participants_phone_idx" ON "guest_participants"("phone");

-- CreateIndex
CREATE UNIQUE INDEX "guest_participants_sessionId_deviceKey_key" ON "guest_participants"("sessionId", "deviceKey");

-- CreateIndex
CREATE INDEX "guest_verifications_tableId_phone_idx" ON "guest_verifications"("tableId", "phone");

-- CreateIndex
CREATE INDEX "guest_order_requests_outletId_status_idx" ON "guest_order_requests"("outletId", "status");

-- CreateIndex
CREATE INDEX "guest_order_requests_orderId_idx" ON "guest_order_requests"("orderId");

-- CreateIndex
CREATE UNIQUE INDEX "guest_order_requests_sessionId_roundKey_key" ON "guest_order_requests"("sessionId", "roundKey");

-- CreateIndex
CREATE INDEX "service_requests_outletId_status_idx" ON "service_requests"("outletId", "status");

-- CreateIndex
CREATE INDEX "service_requests_sessionId_idx" ON "service_requests"("sessionId");

-- CreateIndex
CREATE UNIQUE INDEX "dining_tables_qrToken_key" ON "dining_tables"("qrToken");

-- CreateIndex
CREATE INDEX "order_items_guestRequestId_idx" ON "order_items"("guestRequestId");

-- CreateIndex
CREATE INDEX "orders_guestSessionId_idx" ON "orders"("guestSessionId");

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_guestSessionId_fkey" FOREIGN KEY ("guestSessionId") REFERENCES "guest_sessions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "guest_sessions" ADD CONSTRAINT "guest_sessions_tableId_fkey" FOREIGN KEY ("tableId") REFERENCES "dining_tables"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "guest_participants" ADD CONSTRAINT "guest_participants_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "guest_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "guest_order_requests" ADD CONSTRAINT "guest_order_requests_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "guest_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "guest_order_requests" ADD CONSTRAINT "guest_order_requests_participantId_fkey" FOREIGN KEY ("participantId") REFERENCES "guest_participants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_requests" ADD CONSTRAINT "service_requests_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "guest_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Permission guests.orders.confirm (PLAN.md 2.7): sits right after displays.control (sortOrder 12)
UPDATE "permissions" SET "sortOrder" = "sortOrder" + 1 WHERE "sortOrder" >= 13;

INSERT INTO "permissions" ("key", "group", "label", "description", "limitUnit", "sortOrder") VALUES
  ('guests.orders.confirm', 'Guests & displays', 'Confirm guest QR orders', NULL, NULL, 13);

INSERT INTO "persona_permissions" ("personaId", "permissionKey", "level", "limitValue")
SELECT p."id", v."permissionKey", v."level"::"AccessLevel", NULL::DECIMAL(12,2)
FROM "personas" p
JOIN (VALUES
  ('admin', 'guests.orders.confirm', 'EDIT'),
  ('manager', 'guests.orders.confirm', 'EDIT'),
  ('captain', 'guests.orders.confirm', 'EDIT'),
  ('waiter', 'guests.orders.confirm', 'EDIT'),
  ('cashier', 'guests.orders.confirm', 'VIEW')
) AS v("personaKey", "permissionKey", "level") ON v."personaKey" = p."key"
ON CONFLICT DO NOTHING;
