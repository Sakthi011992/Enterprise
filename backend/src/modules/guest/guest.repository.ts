import { Injectable } from '@nestjs/common';
import { GuestRequestStatus, Prisma, ServiceRequestStatus, ServiceRequestType } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

const OPEN_ORDER = ['OPEN', 'SENT', 'BILLED', 'PENDING', 'PARTIALLY_PAID'];

/** All Prisma access for guest ordering, the staff guest-request API and the session lifecycle. */
@Injectable()
export class GuestRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn, { timeout: 20_000 });
  }

  // ---------------------------------------------------------------- tables, orders, sessions

  findTable(tableId: string) {
    return this.prisma.diningTable.findFirst({
      where: { id: tableId },
      select: {
        id: true,
        name: true,
        outletId: true,
        tenantId: true,
        areaId: true,
        status: true,
        guestPin: true,
        qrToken: true,
        qrEnabled: true,
        area: { select: { name: true } },
      },
    });
  }

  tablesForSheet(outletId: string, areaId?: string) {
    return this.prisma.diningTable.findMany({
      where: { outletId, isActive: true, ...(areaId ? { areaId } : {}) },
      orderBy: [{ name: 'asc' }],
      select: { id: true, name: true, qrToken: true, qrEnabled: true, area: { select: { name: true } } },
    });
  }

  orderState(orderId: string) {
    return this.prisma.order.findFirst({
      where: { id: orderId },
      select: {
        id: true,
        status: true,
        tableId: true,
        outletId: true,
        tenantId: true,
        guestSessionId: true,
        waiterId: true,
        table: { select: { id: true, status: true, guestPin: true } },
      },
    });
  }

  openOrderOnTable(tableId: string) {
    return this.prisma.order.findFirst({
      where: { tableId, status: { in: OPEN_ORDER as any } },
      orderBy: { createdAt: 'asc' },
      select: { id: true, status: true, guestSessionId: true, waiterId: true },
    });
  }

  countOpenOrdersOnTable(tableId: string) {
    return this.prisma.order.count({ where: { tableId, status: { in: OPEN_ORDER as any } } });
  }

  async linkOrderToSession(orderId: string, sessionId: string) {
    await this.prisma.order.update({ where: { id: orderId }, data: { guestSessionId: sessionId } });
    await this.prisma.guestSession.update({ where: { id: sessionId }, data: { orderId } });
  }

  setOrderWaiterIfEmpty(orderId: string, waiterId: string) {
    return this.prisma.order.updateMany({ where: { id: orderId, waiterId: null }, data: { waiterId } });
  }

  findSession(id: string) {
    return this.prisma.guestSession.findFirst({ where: { id } });
  }

  openSessionForTable(tableId: string) {
    return this.prisma.guestSession.findFirst({ where: { tableId, status: 'OPEN' }, orderBy: { createdAt: 'desc' } });
  }

  moveSession(sessionId: string, data: { tableId?: string; orderId?: string }) {
    return this.prisma.guestSession.update({ where: { id: sessionId }, data });
  }

  setAgeConfirmed(sessionId: string, at: Date) {
    return this.prisma.guestSession.update({ where: { id: sessionId }, data: { ageConfirmedAt: at } });
  }

  /** Gives a table a new QR token and clears its PIN (no session change). */
  rotateTableQr(tableId: string, qrToken: string) {
    return this.prisma.diningTable.update({ where: { id: tableId }, data: { qrToken, guestPin: null } });
  }

  /**
   * Closes a session: CLOSED, the table gets a new QR token and no PIN, pending rounds EXPIRED and
   * open service requests DONE. Returns false when the session was not open.
   */
  closeSession(sessionId: string, tableId: string, newQrToken: string, now: Date) {
    return this.prisma.$transaction(async (tx) => {
      const n = await tx.guestSession.updateMany({
        where: { id: sessionId, status: 'OPEN' },
        data: { status: 'CLOSED', closedAt: now },
      });
      if (n.count === 0) return false;
      await tx.diningTable.updateMany({ where: { id: tableId }, data: { qrToken: newQrToken, guestPin: null } });
      await tx.guestOrderRequest.updateMany({
        where: { sessionId, status: 'PENDING' },
        data: { status: 'EXPIRED', decidedAt: now },
      });
      await tx.serviceRequest.updateMany({
        where: { sessionId, status: { in: ['OPEN', 'ACKNOWLEDGED'] } },
        data: { status: 'DONE', doneAt: now },
      });
      return true;
    });
  }

  /** OPEN sessions created before `before`, nobody seen since, and no open order. */
  idleSessions(before: Date) {
    return this.prisma.guestSession.findMany({
      where: {
        status: 'OPEN',
        createdAt: { lt: before },
        participants: { every: { lastSeenAt: { lt: before } } },
        orders: { none: { status: { in: OPEN_ORDER as any } } },
      },
      select: { id: true, tableId: true, tenantId: true },
    });
  }

  blankOldPhones(before: Date) {
    return this.prisma.guestParticipant.updateMany({
      where: { joinedAt: { lt: before }, NOT: { phone: '' } },
      data: { phone: '' },
    });
  }

  findQrGuestUser(tenantId: string) {
    return this.prisma.user.findFirst({
      where: { tenantId, username: { startsWith: 'qr-guest' } },
      orderBy: { username: 'asc' },
      select: { id: true, username: true },
    });
  }

  findParticipant(id: string) {
    return this.prisma.guestParticipant.findFirst({ where: { id } });
  }

  userNames(ids: string[]) {
    if (!ids.length) return Promise.resolve([] as { id: string; displayName: string | null; username: string }[]);
    return this.prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, displayName: true, username: true } });
  }

  // ---------------------------------------------------------------- menu lookups

  async featuredProductIds(now: Date): Promise<Set<string>> {
    const rows = await this.prisma.featuredItem.findMany({
      where: {
        isActive: true,
        AND: [
          { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
          { OR: [{ endsAt: null }, { endsAt: { gt: now } }] },
        ],
      },
      select: { productId: true },
    });
    return new Set(rows.map((r) => r.productId));
  }

  countParticipants(sessionId: string) {
    return this.prisma.guestParticipant.count({ where: { sessionId } });
  }

  touchParticipant(id: string, at: Date) {
    return this.prisma.guestParticipant.updateMany({ where: { id }, data: { lastSeenAt: at } });
  }

  categoryTaxClasses() {
    return this.prisma.category.findMany({ where: { isActive: true }, select: { id: true, taxClassId: true } });
  }

  modifierChannels() {
    return this.prisma.modifierGroup.findMany({ where: { isActive: true }, select: { id: true, showOn: true } });
  }

  // ---------------------------------------------------------------- rounds

  findRequestByKey(sessionId: string, roundKey: string) {
    return this.prisma.guestOrderRequest.findFirst({ where: { sessionId, roundKey } });
  }

  createRequest(data: Prisma.GuestOrderRequestUncheckedCreateInput) {
    return this.prisma.guestOrderRequest.create({ data });
  }

  deleteRequest(id: string) {
    return this.prisma.guestOrderRequest.deleteMany({ where: { id } });
  }

  findRequest(id: string) {
    return this.prisma.guestOrderRequest.findFirst({ where: { id }, include: { participant: true, session: true } });
  }

  /** Status change guarded by the current status. True when this call won the race. */
  async transitionRequest(id: string, from: GuestRequestStatus[], data: Prisma.GuestOrderRequestUncheckedUpdateInput) {
    const r = await this.prisma.guestOrderRequest.updateMany({ where: { id, status: { in: from } }, data });
    return r.count > 0;
  }

  async claimRequest(id: string, userId: string) {
    const r = await this.prisma.guestOrderRequest.updateMany({
      where: { id, status: 'PENDING', OR: [{ claimedById: null }, { claimedById: userId }] },
      data: { claimedById: userId },
    });
    return r.count > 0;
  }

  requestsForOrder(orderId: string) {
    return this.prisma.guestOrderRequest.findMany({
      where: { orderId },
      orderBy: { createdAt: 'asc' },
      include: { participant: { select: { name: true } } },
    });
  }

  listRequests(outletId: string, statuses: GuestRequestStatus[]) {
    return this.prisma.guestOrderRequest.findMany({
      where: { outletId, status: { in: statuses } },
      orderBy: { createdAt: 'asc' },
      include: { participant: true, session: true },
    });
  }

  expiredPending(now: Date) {
    return this.prisma.guestOrderRequest.findMany({
      where: { status: 'PENDING', expiresAt: { lt: now } },
      include: { participant: true, session: true },
    });
  }

  ticketsForOrder(orderId: string) {
    return this.prisma.ticket.findMany({
      where: { orderId, isCancellation: false },
      orderBy: { createdAt: 'asc' },
      select: { id: true, items: true, kdsStatus: true, createdAt: true, startedAt: true, readyAt: true, servedAt: true },
    });
  }

  // ---------------------------------------------------------------- service requests

  findOpenServiceRequest(sessionId: string, type: ServiceRequestType) {
    return this.prisma.serviceRequest.findFirst({
      where: { sessionId, type, status: { in: ['OPEN', 'ACKNOWLEDGED'] } },
      orderBy: { createdAt: 'desc' },
    });
  }

  createServiceRequest(data: Prisma.ServiceRequestUncheckedCreateInput) {
    return this.prisma.serviceRequest.create({ data });
  }

  findServiceRequest(id: string) {
    return this.prisma.serviceRequest.findFirst({ where: { id } });
  }

  updateServiceRequest(id: string, data: Prisma.ServiceRequestUncheckedUpdateInput) {
    return this.prisma.serviceRequest.update({ where: { id }, data });
  }

  listServiceRequests(outletId: string, statuses: ServiceRequestStatus[]) {
    return this.prisma.serviceRequest.findMany({ where: { outletId, status: { in: statuses } }, orderBy: { createdAt: 'asc' } });
  }

  tableNames(ids: string[]) {
    if (!ids.length) return Promise.resolve([] as { id: string; name: string }[]);
    return this.prisma.diningTable.findMany({ where: { id: { in: ids } }, select: { id: true, name: true } });
  }

  /** Per table: pending rounds and whether an open BILL request exists (floor badges). */
  async floorGuestInfo(tableIds: string[]) {
    const pending = new Map<string, number>();
    const bill = new Set<string>();
    if (!tableIds.length) return { pending, bill };
    const [rounds, bills] = await Promise.all([
      this.prisma.guestOrderRequest.findMany({
        where: { status: 'PENDING', session: { status: 'OPEN', tableId: { in: tableIds } } },
        select: { session: { select: { tableId: true } } },
      }),
      this.prisma.serviceRequest.findMany({
        where: { type: 'BILL', status: { in: ['OPEN', 'ACKNOWLEDGED'] }, tableId: { in: tableIds } },
        select: { tableId: true },
      }),
    ]);
    for (const r of rounds) pending.set(r.session.tableId, (pending.get(r.session.tableId) ?? 0) + 1);
    for (const b of bills) bill.add(b.tableId);
    return { pending, bill };
  }
}
