import { Injectable } from '@nestjs/common';
import { BottleLockerEvent, LockerStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { LockerRow } from './tab-view';

type Db = Prisma.TransactionClient;

const WITH_EVENTS = { events: { orderBy: { createdAt: 'asc' as const } } };

/** Data access for bottle locker entries and their events. */
@Injectable()
export class LockerRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

  listEntries(outletId: string, where: { status?: LockerStatus; search?: string }): Promise<LockerRow[]> {
    const search = where.search
      ? {
          OR: [
            { guestName: { contains: where.search, mode: 'insensitive' as const } },
            { bottleName: { contains: where.search, mode: 'insensitive' as const } },
            { cardLast4: where.search },
          ],
        }
      : {};
    return this.prisma.bottleLockerEntry.findMany({
      where: { outletId, ...(where.status ? { status: where.status } : {}), ...search },
      include: WITH_EVENTS,
      orderBy: { storedAt: 'desc' },
    });
  }

  findEntry(id: string, outletId: string, db: Db = this.prisma): Promise<LockerRow | null> {
    return db.bottleLockerEntry.findFirst({ where: { id, outletId }, include: WITH_EVENTS });
  }

  createEntry(tx: Db, data: Prisma.BottleLockerEntryUncheckedCreateInput): Promise<LockerRow> {
    return tx.bottleLockerEntry.create({ data, include: WITH_EVENTS });
  }

  updateEntry(tx: Db, id: string, data: Prisma.BottleLockerEntryUncheckedUpdateInput): Promise<LockerRow> {
    return tx.bottleLockerEntry.update({ where: { id }, data, include: WITH_EVENTS });
  }

  addEvent(tx: Db, data: Prisma.BottleLockerEventUncheckedCreateInput): Promise<BottleLockerEvent> {
    return tx.bottleLockerEvent.create({ data });
  }

  /** Display names for the users who appear on events. */
  async userNames(ids: string[]): Promise<Map<string, string>> {
    const unique = [...new Set(ids)];
    if (unique.length === 0) return new Map();
    const users = await this.prisma.user.findMany({
      where: { id: { in: unique } },
      select: { id: true, displayName: true, username: true },
    });
    return new Map(users.map((u) => [u.id, u.displayName ?? u.username]));
  }
}
