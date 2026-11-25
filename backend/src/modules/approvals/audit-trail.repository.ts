import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

export interface AuditRow {
  tenantId: string;
  actorId: string | null;
  action: string;
  entity: string;
  entityId: string | null;
  metadata: Prisma.InputJsonValue;
}

/** Data access for audit_logs. Phase 2 writes an entry for every void, move, merge, refund, approval and no-sale. */
@Injectable()
export class AuditTrailRepository {
  constructor(private prisma: PrismaService) {}

  insert(tx: Prisma.TransactionClient, row: AuditRow) {
    return tx.auditLog.create({ data: row });
  }
}
