-- CreateEnum
CREATE TYPE "LogoRole" AS ENUM ('WORDMARK', 'ICON_MARK');

-- CreateEnum
CREATE TYPE "LogoVariant" AS ENUM ('LIGHT', 'DARK');

-- CreateEnum
CREATE TYPE "NumberResetPeriod" AS ENUM ('NEVER', 'CALENDAR_YEAR', 'FINANCIAL_YEAR');

-- CreateEnum
CREATE TYPE "TaxBreakdownMode" AS ENUM ('SINGLE_LINE', 'SPLIT_COMPONENTS');

-- CreateEnum
CREATE TYPE "RoundingRule" AS ENUM ('ROUND_PER_LINE', 'ROUND_TOTAL');

-- CreateEnum
CREATE TYPE "InvoiceStatus" AS ENUM ('ISSUED', 'VOIDED', 'CREDIT_NOTE', 'REPLACEMENT');

-- CreateEnum
CREATE TYPE "DownloadContext" AS ENUM ('SINGLE', 'BULK_EXPORT');

-- CreateEnum
CREATE TYPE "LoginMethod" AS ENUM ('STATIC', 'GOOGLE');

-- CreateEnum
CREATE TYPE "ImageSource" AS ENUM ('UPLOAD', 'STOCK');

-- AlterEnum
ALTER TYPE "PaymentMethod" ADD VALUE 'CARD';

-- AlterTable
ALTER TABLE "payments" ADD COLUMN     "gatewayEventIds" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- AlterTable
ALTER TABLE "users" ALTER COLUMN "email" DROP NOT NULL,
ALTER COLUMN "passwordHash" DROP NOT NULL;

-- CreateTable
CREATE TABLE "brand_logos" (
    "id" TEXT NOT NULL,
    "themeId" TEXT NOT NULL,
    "role" "LogoRole" NOT NULL,
    "variant" "LogoVariant" NOT NULL,
    "mimeType" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "contentHash" TEXT NOT NULL,
    "blobPath" TEXT NOT NULL,
    "width" INTEGER,
    "height" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "brand_logos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "translation_keys" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "description" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "translation_keys_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "translation_values" (
    "id" TEXT NOT NULL,
    "keyId" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "translation_values_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_locale_preferences" (
    "userId" TEXT NOT NULL,
    "locale" TEXT NOT NULL DEFAULT 'en',
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_locale_preferences_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "invoice_country_profiles" (
    "id" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "numberPrefix" TEXT NOT NULL,
    "resetPeriod" "NumberResetPeriod" NOT NULL DEFAULT 'CALENDAR_YEAR',
    "taxBreakdownMode" "TaxBreakdownMode" NOT NULL DEFAULT 'SINGLE_LINE',
    "roundingRule" "RoundingRule" NOT NULL DEFAULT 'ROUND_PER_LINE',
    "retentionYears" INTEGER NOT NULL DEFAULT 7,
    "requiredFields" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "invoice_country_profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invoice_counters" (
    "id" TEXT NOT NULL,
    "countryProfileId" TEXT NOT NULL,
    "periodKey" TEXT NOT NULL,
    "lastSeq" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "invoice_counters_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invoices" (
    "id" TEXT NOT NULL,
    "invoiceNumber" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "countryProfileId" TEXT NOT NULL,
    "status" "InvoiceStatus" NOT NULL DEFAULT 'ISSUED',
    "taxBreakdown" JSONB NOT NULL,
    "subtotal" DECIMAL(12,2) NOT NULL,
    "taxAmount" DECIMAL(12,2) NOT NULL,
    "grandTotal" DECIMAL(12,2) NOT NULL,
    "currencyCode" TEXT NOT NULL DEFAULT 'INR',
    "blobPath" TEXT,
    "contentHash" TEXT,
    "issuedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "voidedAt" TIMESTAMP(3),
    "replacedById" TEXT,

    CONSTRAINT "invoices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invoice_download_logs" (
    "id" TEXT NOT NULL,
    "invoiceId" TEXT NOT NULL,
    "context" "DownloadContext" NOT NULL,
    "actorId" TEXT,
    "ipAddress" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "invoice_download_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_method_configs" (
    "id" TEXT NOT NULL,
    "method" "PaymentMethod" NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "storeId" TEXT NOT NULL DEFAULT 'default',

    CONSTRAINT "payment_method_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_gateway_profiles" (
    "id" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "gateway" TEXT NOT NULL,
    "config" JSONB NOT NULL DEFAULT '{}',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "payment_gateway_profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "login_method_configs" (
    "method" "LoginMethod" NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "login_method_configs_pkey" PRIMARY KEY ("method")
);

-- CreateTable
CREATE TABLE "oauth_accounts" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "provider" "LoginMethod" NOT NULL,
    "providerUserId" TEXT NOT NULL,
    "email" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "oauth_accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product_images" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "isPrimary" BOOLEAN NOT NULL DEFAULT false,
    "source" "ImageSource" NOT NULL DEFAULT 'UPLOAD',
    "mimeType" TEXT NOT NULL DEFAULT 'image/webp',
    "sizeBytes" INTEGER NOT NULL DEFAULT 0,
    "contentHash" TEXT NOT NULL,
    "blobPath" TEXT NOT NULL,
    "photographerName" TEXT,
    "photographerUrl" TEXT,
    "sourceUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "product_images_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "kiosk_configs" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "storeId" TEXT NOT NULL DEFAULT 'default',
    "orderingEnabled" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "kiosk_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "featured_items" (
    "id" TEXT NOT NULL,
    "storeId" TEXT NOT NULL DEFAULT 'default',
    "productId" TEXT NOT NULL,
    "label" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "startsAt" TIMESTAMP(3),
    "endsAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "featured_items_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "brand_logos_themeId_role_variant_key" ON "brand_logos"("themeId", "role", "variant");

-- CreateIndex
CREATE UNIQUE INDEX "translation_keys_key_key" ON "translation_keys"("key");

-- CreateIndex
CREATE INDEX "translation_values_locale_idx" ON "translation_values"("locale");

-- CreateIndex
CREATE UNIQUE INDEX "translation_values_keyId_locale_key" ON "translation_values"("keyId", "locale");

-- CreateIndex
CREATE UNIQUE INDEX "invoice_country_profiles_countryCode_key" ON "invoice_country_profiles"("countryCode");

-- CreateIndex
CREATE UNIQUE INDEX "invoice_counters_countryProfileId_periodKey_key" ON "invoice_counters"("countryProfileId", "periodKey");

-- CreateIndex
CREATE UNIQUE INDEX "invoices_invoiceNumber_key" ON "invoices"("invoiceNumber");

-- CreateIndex
CREATE UNIQUE INDEX "invoices_replacedById_key" ON "invoices"("replacedById");

-- CreateIndex
CREATE INDEX "invoices_orderId_idx" ON "invoices"("orderId");

-- CreateIndex
CREATE INDEX "invoices_status_idx" ON "invoices"("status");

-- CreateIndex
CREATE INDEX "invoices_issuedAt_idx" ON "invoices"("issuedAt");

-- CreateIndex
CREATE INDEX "invoice_download_logs_invoiceId_idx" ON "invoice_download_logs"("invoiceId");

-- CreateIndex
CREATE UNIQUE INDEX "payment_method_configs_storeId_method_key" ON "payment_method_configs"("storeId", "method");

-- CreateIndex
CREATE UNIQUE INDEX "payment_gateway_profiles_countryCode_key" ON "payment_gateway_profiles"("countryCode");

-- CreateIndex
CREATE INDEX "oauth_accounts_userId_idx" ON "oauth_accounts"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "oauth_accounts_provider_providerUserId_key" ON "oauth_accounts"("provider", "providerUserId");

-- CreateIndex
CREATE INDEX "product_images_productId_idx" ON "product_images"("productId");

-- CreateIndex
CREATE UNIQUE INDEX "kiosk_configs_userId_key" ON "kiosk_configs"("userId");

-- CreateIndex
CREATE INDEX "featured_items_storeId_isActive_idx" ON "featured_items"("storeId", "isActive");

-- AddForeignKey
ALTER TABLE "brand_logos" ADD CONSTRAINT "brand_logos_themeId_fkey" FOREIGN KEY ("themeId") REFERENCES "themes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "translation_values" ADD CONSTRAINT "translation_values_keyId_fkey" FOREIGN KEY ("keyId") REFERENCES "translation_keys"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_locale_preferences" ADD CONSTRAINT "user_locale_preferences_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoice_counters" ADD CONSTRAINT "invoice_counters_countryProfileId_fkey" FOREIGN KEY ("countryProfileId") REFERENCES "invoice_country_profiles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoices" ADD CONSTRAINT "invoices_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoices" ADD CONSTRAINT "invoices_countryProfileId_fkey" FOREIGN KEY ("countryProfileId") REFERENCES "invoice_country_profiles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoices" ADD CONSTRAINT "invoices_replacedById_fkey" FOREIGN KEY ("replacedById") REFERENCES "invoices"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoice_download_logs" ADD CONSTRAINT "invoice_download_logs_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "invoices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "oauth_accounts" ADD CONSTRAINT "oauth_accounts_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product_images" ADD CONSTRAINT "product_images_productId_fkey" FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "kiosk_configs" ADD CONSTRAINT "kiosk_configs_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "featured_items" ADD CONSTRAINT "featured_items_productId_fkey" FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;
