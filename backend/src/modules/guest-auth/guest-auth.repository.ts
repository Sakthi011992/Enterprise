import { Injectable } from '@nestjs/common';
import { GuestVerifyMethod, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

const TABLE_SELECT = {
  id: true,
  tenantId: true,
  outletId: true,
  name: true,
  status: true,
  isActive: true,
  qrEnabled: true,
  qrToken: true,
  guestPin: true,
  outlet: { select: { id: true, name: true, isActive: true } },
} satisfies Prisma.DiningTableSelect;

export type GuestTable = Prisma.DiningTableGetPayload<{ select: typeof TABLE_SELECT }>;

/**
 * Data access for guest auth. Guest routes are public, so there is no tenant in TenantContext and
 * the tenant extension passes queries through; every lookup here is keyed by the table or session.
 */
@Injectable()
export class GuestAuthRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

  findTableByQrToken(qrToken: string): Promise<GuestTable | null> {
    return this.prisma.diningTable.findUnique({ where: { qrToken }, select: TABLE_SELECT });
  }

  findOpenSession(tableId: string) {
    return this.prisma.guestSession.findFirst({
      where: { tableId, status: 'OPEN' },
      orderBy: { createdAt: 'desc' },
    });
  }

  async sessionStatus(sessionId: string): Promise<string | null> {
    const s = await this.prisma.guestSession.findUnique({ where: { id: sessionId }, select: { status: true } });
    return s?.status ?? null;
  }

  async webThemeId(): Promise<string | null> {
    const a = await this.prisma.themeAssignment.findUnique({ where: { platform: 'WEB' }, select: { themeId: true } });
    return a?.themeId ?? null;
  }

  async hasWordmark(themeId: string): Promise<boolean> {
    const n = await this.prisma.brandLogo.count({ where: { themeId, role: 'WORDMARK', variant: 'LIGHT' } });
    return n > 0;
  }

  /** Most recent lock on this table for the phone or device that is still in force. */
  findActiveLock(tableId: string, phone: string, deviceKey: string, now: Date) {
    return this.prisma.guestVerification.findFirst({
      where: { tableId, lockedUntil: { gt: now }, OR: [{ phone }, { deviceKey }] },
      orderBy: { lockedUntil: 'desc' },
      select: { lockedUntil: true },
    });
  }

  createVerification(data: Prisma.GuestVerificationUncheckedCreateInput) {
    return this.prisma.guestVerification.create({ data });
  }

  findVerification(id: string) {
    return this.prisma.guestVerification.findUnique({ where: { id } });
  }

  recordFailedAttempt(id: string, attempts: number, lockedUntil: Date | null) {
    return this.prisma.guestVerification.update({ where: { id }, data: { attempts, lockedUntil } });
  }

  /**
   * Marks the challenge verified, then opens or joins the table's session and creates or updates
   * the participant for the device. The table row is locked so two phones scanning at once join
   * the same session.
   */
  async completeVerification(input: {
    verificationId: string;
    table: { id: string; tenantId: string; outletId: string };
    name: string;
    phone: string;
    deviceKey: string;
    consentAt: Date;
    method: GuestVerifyMethod;
    now: Date;
  }) {
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "dining_tables" WHERE "id" = ${input.table.id} FOR UPDATE`;
      await tx.guestVerification.update({ where: { id: input.verificationId }, data: { verifiedAt: input.now } });

      const session =
        (await tx.guestSession.findFirst({
          where: { tableId: input.table.id, status: 'OPEN' },
          orderBy: { createdAt: 'desc' },
        })) ??
        (await tx.guestSession.create({
          data: { tenantId: input.table.tenantId, outletId: input.table.outletId, tableId: input.table.id },
        }));

      const fields = {
        name: input.name,
        phone: input.phone,
        verifiedAt: input.now,
        verifyMethod: input.method,
        consentAt: input.consentAt,
        lastSeenAt: input.now,
      };
      const participant = await tx.guestParticipant.upsert({
        where: { sessionId_deviceKey: { sessionId: session.id, deviceKey: input.deviceKey } },
        create: { sessionId: session.id, deviceKey: input.deviceKey, ...fields },
        update: fields,
      });
      return { session, participant };
    });
  }

  setGuestPin(tableId: string, guestPin: string | null) {
    return this.prisma.diningTable.update({ where: { id: tableId }, data: { guestPin }, select: { id: true, guestPin: true } });
  }
}
