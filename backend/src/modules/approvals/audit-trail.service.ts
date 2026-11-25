import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuditTrailRepository } from './audit-trail.repository';

export interface AuditEntry {
  tenantId: string;
  actorId: string | null;
  action: string;
  entity: string;
  entityId: string | null;
  metadata?: Record<string, unknown>;
}

/** Writes audit rows inside the caller's transaction, so a rolled-back change leaves no audit trace. */
@Injectable()
export class AuditTrailService {
  constructor(private repo: AuditTrailRepository) {}

  record(tx: Prisma.TransactionClient, entry: AuditEntry) {
    return this.repo.insert(tx, {
      tenantId: entry.tenantId,
      actorId: entry.actorId,
      action: entry.action,
      entity: entry.entity,
      entityId: entry.entityId,
      metadata: (entry.metadata ?? {}) as Prisma.InputJsonValue,
    });
  }
}
