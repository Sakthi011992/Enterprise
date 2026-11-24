-- CreateEnum
CREATE TYPE "AppFeature" AS ENUM ('DASHBOARD', 'PRODUCTS', 'TAX', 'USERS', 'ORDERS', 'APPEARANCE');

-- CreateTable
CREATE TABLE "user_feature_grants" (
    "userId" TEXT NOT NULL,
    "feature" "AppFeature" NOT NULL,
    "grantedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_feature_grants_pkey" PRIMARY KEY ("userId","feature")
);

-- CreateIndex
CREATE INDEX "user_feature_grants_userId_idx" ON "user_feature_grants"("userId");

-- AddForeignKey
ALTER TABLE "user_feature_grants" ADD CONSTRAINT "user_feature_grants_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
