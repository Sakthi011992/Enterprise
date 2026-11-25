import { Injectable } from '@nestjs/common';
import { ApprovalStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

/** Data access for approvals, the notifications they raise, and the approver's outlet access. */
@Injectable()
export class ApprovalsRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

  createApproval(tx: Prisma.TransactionClient, data: Prisma.ApprovalUncheckedCreateInput) {
    return tx.approval.create({ data });
  }

  findApproval(id: string, outletId: string) {
    return this.prisma.approval.findFirst({ where: { id, outletId } });
  }

  updateApproval(tx: Prisma.TransactionClient, id: string, data: Prisma.ApprovalUncheckedUpdateInput) {
    return tx.approval.update({ where: { id }, data });
  }

  /** Marks an approval used. Returns 0 if it was already used (single-use guard, race-safe). */
  consume(id: string, now: Date) {
    return this.prisma.approval.updateMany({ where: { id, consumedAt: null }, data: { consumedAt: now } }).then((r) => r.count);
  }

  listApprovals(outletId: string, status: ApprovalStatus | undefined, take: number) {
    return this.prisma.approval.findMany({
      where: { outletId, ...(status ? { status } : {}) },
      orderBy: { createdAt: 'desc' },
      take,
    });
  }

  /** Marks pending approvals past their expiry as EXPIRED. Called before reads so polling sees the truth. */
  expireStale(outletId: string, now: Date) {
    return this.prisma.approval.updateMany({
      where: { outletId, status: ApprovalStatus.PENDING, expiresAt: { lt: now } },
      data: { status: ApprovalStatus.EXPIRED },
    });
  }

  createNotification(tx: Prisma.TransactionClient, data: Prisma.NotificationUncheckedCreateInput) {
    return tx.notification.create({ data });
  }

  /** The user's access to this outlet, with the user row for the active and tenant checks. */
  findUserOutlet(userId: string, outletId: string) {
    return this.prisma.userOutlet.findUnique({
      where: { userId_outletId: { userId, outletId } },
      include: { user: true },
    });
  }
}
