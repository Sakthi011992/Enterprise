import { Injectable } from '@nestjs/common';
import { Approval, ApprovalStatus, Prisma } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { PermissionsService } from '../personas/permissions.service';
import { levelAtLeast } from '../../common/permissions/catalog';
import { AuthRepository } from '../auth/auth.repository';
import { AuditTrailService } from './audit-trail.service';
import {
  ApprovalKind,
  APPROVAL_PERMISSION,
  APPROVAL_TTL_MS,
  canonicalPayload,
  validateApprovalPayload,
} from './approval-payload';
import { ApprovalsRepository } from './approvals.repository';
import { CreateApprovalDto, DecideApprovalDto, ManagerPinApprovalDto } from './dto/approval.dto';

// Same lockout rule as the Phase 1 tablet PIN login (AuthService.pinLogin). Keep in step with it.
const MAX_PIN_ATTEMPTS = 3;
const PIN_LOCK_MS = 5 * 60_000;

const TITLE: Record<ApprovalKind, string> = {
  DISCOUNT: 'Discount needs approval',
  VOID: 'Void needs approval',
  REFUND: 'Refund needs approval',
  NO_SALE: 'Cash drawer open needs approval',
  TAB_NO_SECURITY: 'Bar tab without security needs approval',
};

export function approvalView(a: Approval) {
  return {
    id: a.id,
    type: a.type,
    status: a.status,
    orderId: a.orderId,
    reason: a.reason,
    payload: a.payload,
    requestedById: a.requestedById,
    approverId: a.approverId,
    createdAt: a.createdAt.toISOString(),
    decidedAt: a.decidedAt ? a.decidedAt.toISOString() : null,
    expiresAt: a.expiresAt.toISOString(),
  };
}

@Injectable()
export class ApprovalsService {
  constructor(
    private repo: ApprovalsRepository,
    private authRepo: AuthRepository,
    private permissions: PermissionsService,
    private audit: AuditTrailService,
  ) {}

  /** A cashier or waiter asks a manager. Creates a PENDING approval and a notification for approvers. */
  async create(auth: AuthUser, dto: CreateApprovalDto) {
    const type = dto.type as ApprovalKind;
    validateApprovalPayload(type, dto.payload);
    const now = new Date();

    const approval = await this.repo.transaction(async (tx) => {
      const row = await this.repo.createApproval(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        orderId: dto.orderId ?? null,
        type: dto.type,
        status: ApprovalStatus.PENDING,
        requestedById: auth.userId,
        payload: dto.payload as Prisma.InputJsonValue,
        reason: dto.reason,
        expiresAt: new Date(now.getTime() + APPROVAL_TTL_MS),
      });
      await this.repo.createNotification(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        userId: null,
        permissionKey: APPROVAL_PERMISSION[type],
        type: 'approval',
        title: TITLE[type],
        body: dto.reason,
        data: { approvalId: row.id, orderId: dto.orderId ?? null },
      });
      return row;
    });
    return approvalView(approval);
  }

  async get(auth: AuthUser, id: string) {
    await this.repo.expireStale(auth.outletId, new Date());
    const approval = await this.repo.findApproval(id, auth.outletId);
    if (!approval) throw apiError(404, 'APPROVAL_NOT_FOUND', 'Approval not found');
    return approvalView(approval);
  }

  async list(auth: AuthUser, status?: ApprovalStatus) {
    await this.repo.expireStale(auth.outletId, new Date());
    const rows = await this.repo.listApprovals(auth.outletId, status, 50);
    return { data: rows.map(approvalView) };
  }

  /** An approver with APPROVE (or EDIT) on the matching key accepts or declines a PENDING approval. */
  async decide(auth: AuthUser, id: string, dto: DecideApprovalDto) {
    const now = new Date();
    await this.repo.expireStale(auth.outletId, now);
    const approval = await this.repo.findApproval(id, auth.outletId);
    if (!approval) throw apiError(404, 'APPROVAL_NOT_FOUND', 'Approval not found');

    const key = APPROVAL_PERMISSION[approval.type as ApprovalKind];
    if (!this.permissions.check(auth, key, 'APPROVE')) {
      throw apiError(403, 'APPROVER_NOT_ALLOWED', 'You cannot approve this request', { permission: key });
    }
    if (approval.status !== ApprovalStatus.PENDING) {
      throw apiError(409, 'APPROVAL_NOT_PENDING', 'This request is no longer pending', { status: approval.status });
    }

    const updated = await this.repo.transaction(async (tx) => {
      const row = await this.repo.updateApproval(tx, id, {
        status: dto.decision,
        approverId: auth.userId,
        decidedAt: now,
      });
      if (dto.decision === 'APPROVED') {
        await this.audit.record(tx, {
          tenantId: auth.tenantId,
          actorId: auth.userId,
          action: 'approval.approved',
          entity: 'Approval',
          entityId: id,
          metadata: { type: approval.type, orderId: approval.orderId },
        });
      }
      return row;
    });
    return approvalView(updated);
  }

  /**
   * Manager at the same device types their PIN. Creates and approves in one step when that manager
   * holds APPROVE for the key. The PIN is checked against the Phase 1 lockout: 3 wrong tries lock the
   * manager's PIN for 5 minutes.
   */
  async approveWithPin(auth: AuthUser, dto: ManagerPinApprovalDto) {
    const type = dto.type as ApprovalKind;
    validateApprovalPayload(type, dto.payload);
    const key = APPROVAL_PERMISSION[type];

    const access = await this.repo.findUserOutlet(dto.managerUserId, auth.outletId);
    if (!access || access.user.tenantId !== auth.tenantId || access.user.deletedAt !== null || !access.user.isActive) {
      throw apiError(403, 'APPROVER_NOT_ALLOWED', 'This person cannot approve at this outlet');
    }
    const matrix = await this.permissions.forPersona(access.personaId);
    if (!levelAtLeast(matrix[key]?.level ?? 'NONE', 'APPROVE')) {
      throw apiError(403, 'APPROVER_NOT_ALLOWED', 'This person cannot approve this request', { permission: key });
    }

    await this.verifyPin(dto.managerUserId, dto.pin);

    const now = new Date();
    const approval = await this.repo.transaction(async (tx) => {
      const row = await this.repo.createApproval(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        orderId: dto.orderId ?? null,
        type: dto.type,
        status: ApprovalStatus.APPROVED,
        requestedById: auth.userId,
        approverId: dto.managerUserId,
        payload: dto.payload as Prisma.InputJsonValue,
        reason: dto.reason,
        createdAt: now,
        decidedAt: now,
        expiresAt: new Date(now.getTime() + APPROVAL_TTL_MS),
      });
      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: dto.managerUserId,
        action: 'approval.pin',
        entity: 'Approval',
        entityId: row.id,
        metadata: { type, orderId: dto.orderId ?? null, requestedById: auth.userId, reason: dto.reason },
      });
      return row;
    });
    return approvalView(approval);
  }

  /**
   * Confirms that an approval cited by an order, payment or cash-drawer request is APPROVED, recent,
   * for this outlet and order, and for exactly the same parameters. Returns the approver's id.
   */
  async assertApproved(
    approvalId: string,
    auth: Pick<AuthUser, 'outletId'>,
    type: ApprovalKind,
    requestPayload: Record<string, unknown>,
    orderId: string | null,
  ): Promise<{ approverId: string | null }> {
    const approval = await this.repo.findApproval(approvalId, auth.outletId);
    const required = () => apiError(403, 'APPROVAL_REQUIRED', 'A manager must approve this', { approvalId });
    if (!approval || approval.type !== type || approval.status !== ApprovalStatus.APPROVED) throw required();
    if (approval.orderId && orderId && approval.orderId !== orderId) throw required();
    if (!approval.decidedAt || approval.decidedAt.getTime() < Date.now() - APPROVAL_TTL_MS) {
      throw apiError(403, 'APPROVAL_EXPIRED', 'This approval is too old, ask again', { approvalId });
    }
    if (canonicalPayload(type, approval.payload) !== canonicalPayload(type, requestPayload)) {
      throw apiError(403, 'APPROVAL_MISMATCH', 'The approval does not match this request', { approvalId });
    }
    // Single use: a second request citing the same approval is refused.
    if ((await this.repo.consume(approvalId, new Date())) === 0) {
      throw apiError(403, 'APPROVAL_USED', 'This approval was already used, ask again', { approvalId });
    }
    return { approverId: approval.approverId };
  }

  /** Phase 1 PIN rule for a user: bcrypt check, 3 wrong tries lock for 5 minutes. */
  private async verifyPin(userId: string, pin: string): Promise<void> {
    const staffPin = await this.authRepo.findStaffPin(userId);
    if (!staffPin) throw apiError(401, 'PIN_INVALID', 'Incorrect PIN');

    const now = new Date();
    if (staffPin.lockedUntil && staffPin.lockedUntil > now) throw this.lockedError(staffPin.lockedUntil);
    // An expired lock starts a fresh cycle of attempts.
    let failed = staffPin.lockedUntil ? 0 : staffPin.failedAttempts;

    const ok = await bcrypt.compare(pin, staffPin.pinHash);
    if (ok) {
      await this.authRepo.updateStaffPin(userId, { failedAttempts: 0, lockedUntil: null });
      return;
    }

    failed += 1;
    if (failed >= MAX_PIN_ATTEMPTS) {
      const lockedUntil = new Date(now.getTime() + PIN_LOCK_MS);
      await this.authRepo.updateStaffPin(userId, { failedAttempts: failed, lockedUntil });
      throw this.lockedError(lockedUntil);
    }
    await this.authRepo.updateStaffPin(userId, { failedAttempts: failed, lockedUntil: null });
    throw apiError(401, 'PIN_INVALID', 'Incorrect PIN', { attemptsLeft: MAX_PIN_ATTEMPTS - failed });
  }

  private lockedError(lockedUntil: Date) {
    return apiError(423, 'PIN_LOCKED', 'Too many wrong PINs. Try again later.', {
      lockedUntil: lockedUntil.toISOString(),
    });
  }
}
