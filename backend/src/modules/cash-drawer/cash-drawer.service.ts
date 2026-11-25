import { Injectable } from '@nestjs/common';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { levelAtLeast } from '../../common/permissions/catalog';
import { ApprovalsService } from '../approvals/approvals.service';
import { AuditTrailService } from '../approvals/audit-trail.service';
import { PrintService } from '../printing/print.service';
import { CashDrawerRepository } from './cash-drawer.repository';
import { OpenDrawerDto } from './dto/cash-drawer.dto';

@Injectable()
export class CashDrawerService {
  constructor(
    private repo: CashDrawerRepository,
    private approvals: ApprovalsService,
    private audit: AuditTrailService,
    private print: PrintService,
  ) {}

  /**
   * "No sale" drawer open. Someone with sales.payments.take EDIT opens directly. Anyone else needs a
   * NO_SALE approval. Every open is audited.
   */
  async open(auth: AuthUser, dto: OpenDrawerDto) {
    const level = auth.permissions['sales.payments.take']?.level ?? 'NONE';
    let approverId: string | null = null;
    if (!levelAtLeast(level, 'EDIT')) {
      if (!dto.approvalId) {
        throw apiError(403, 'APPROVAL_REQUIRED', 'A manager must approve opening the drawer', { required: 'EDIT' });
      }
      const approval = await this.approvals.assertApproved(dto.approvalId, auth, 'NO_SALE', { reason: dto.reason }, null);
      approverId = approval.approverId;
    }

    await this.repo.transaction((tx) =>
      this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'cash_drawer.no_sale',
        entity: 'Outlet',
        entityId: auth.outletId,
        metadata: { reason: dto.reason, approvalId: dto.approvalId ?? null, approverId },
      }),
    );
    await this.print.openDrawer(auth.outletId, `No sale: ${dto.reason}`);
    return { success: true };
  }
}
