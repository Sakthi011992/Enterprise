import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

/** Per-tenant document counters (PO, GRN, DN, TR). Call inside the transaction that uses the number. */
@Injectable()
export class DocumentNumberRepository {
  /** Atomically increments the counter and returns the new value (the first number is 1). */
  async next(tx: Prisma.TransactionClient, tenantId: string, key: string): Promise<number> {
    const row = await tx.documentCounter.upsert({
      where: { tenantId_key: { tenantId, key } },
      create: { tenantId, key, value: 1 },
      update: { value: { increment: 1 } },
      select: { value: true },
    });
    return row.value;
  }
}
