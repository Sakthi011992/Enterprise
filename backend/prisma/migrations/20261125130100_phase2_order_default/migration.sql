-- Phase 2: new orders start at OPEN. Split from 20261125130000_phase2_pos_core because values
-- added with ALTER TYPE ... ADD VALUE cannot be used in the same transaction that adds them.
-- Existing rows keep their legacy statuses (PENDING, PAID, PARTIALLY_PAID, REFUNDED).

-- AlterTable
ALTER TABLE "orders" ALTER COLUMN "status" SET DEFAULT 'OPEN';
