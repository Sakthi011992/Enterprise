import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { businessDateFor, toDateOnly } from '../../common/pricing/business-date';
import { OrdersRepository } from '../orders/orders.repository';
import { CreateLockerDto, LockerQueryDto, RemoveLockerDto, ServeLockerDto, UpdateLockerDto } from './dto/locker.dto';
import { LockerRepository } from './locker.repository';
import { LockerRow, LockerView, toLockerView } from './tab-view';

/**
 * Bottle locker: a partly used bottle kept for a guest. Every change writes a BottleLockerEvent so the
 * remaining volume can always be traced (STORE, SERVE, ADJUST, REMOVE).
 */
@Injectable()
export class LockerService {
  constructor(
    private repo: LockerRepository,
    private ordersRepo: OrdersRepository,
  ) {}

  async list(q: LockerQueryDto, auth: AuthUser): Promise<LockerView[]> {
    const rows = await this.repo.listEntries(auth.outletId, {
      status: q.status,
      search: q.search?.trim() || undefined,
    });
    const today = await this.today(auth.outletId);
    const names = await this.repo.userNames(rows.flatMap((r) => r.events.map((e) => e.byId)));
    return rows.map((r) => toLockerView(r, today, names));
  }

  async create(dto: CreateLockerDto, auth: AuthUser): Promise<LockerView> {
    if (dto.remainingMl > dto.bottleMl) {
      throw apiError(400, 'INVALID_ML', 'Remaining ml cannot be more than the bottle size', {
        bottleMl: dto.bottleMl,
        remainingMl: dto.remainingMl,
      });
    }
    const today = await this.today(auth.outletId);
    const row = await this.repo.transaction((tx) =>
      this.repo.createEntry(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        guestName: dto.guestName.trim(),
        mobile: dto.mobile ?? null,
        cardLast4: dto.cardLast4 ?? null,
        stockItemId: dto.stockItemId ?? null,
        bottleName: dto.bottleName.trim(),
        bottleMl: dto.bottleMl,
        remainingMl: dto.remainingMl,
        expiresAt: toDateOnly(dto.expiresAt),
        orderItemId: dto.orderItemId ?? null,
        note: dto.note ?? null,
        createdById: auth.userId,
        events: { create: { kind: 'STORE', ml: dto.remainingMl, byId: auth.userId, note: 'Stored' } },
      }),
    );
    return this.viewOf(row, today);
  }

  /** Serves ml from the bottle. Reaching zero finishes the entry. */
  async serve(id: string, dto: ServeLockerDto, auth: AuthUser): Promise<LockerView> {
    const today = await this.today(auth.outletId);
    const row = await this.repo.transaction(async (tx) => {
      const entry = await this.mustFind(id, auth, tx);
      if (entry.status === 'REMOVED') throw apiError(404, 'LOCKER_NOT_FOUND', 'Bottle not found');
      if (entry.status === 'EXPIRED' || this.isExpired(entry, today)) {
        throw apiError(409, 'LOCKER_EXPIRED', 'This bottle has passed its locker date', { expiresAt: entry.expiresAt });
      }
      if (entry.status !== 'ACTIVE' || dto.ml > entry.remainingMl) {
        throw apiError(409, 'NOT_ENOUGH_LEFT', `Only ${entry.remainingMl} ml left`, { remainingMl: entry.remainingMl });
      }

      const left = entry.remainingMl - dto.ml;
      await this.repo.addEvent(tx, { entryId: entry.id, kind: 'SERVE', ml: dto.ml, byId: auth.userId });
      return this.repo.updateEntry(tx, entry.id, { remainingMl: left, status: left === 0 ? 'FINISHED' : 'ACTIVE' });
    });
    return this.viewOf(row, today);
  }

  /**
   * Edits the guest details, the expiry, or the remaining volume. A changed volume writes an ADJUST event
   * for the difference (negative when the bottle was topped down).
   */
  async update(id: string, dto: UpdateLockerDto, auth: AuthUser): Promise<LockerView> {
    const today = await this.today(auth.outletId);
    const row = await this.repo.transaction(async (tx) => {
      const entry = await this.mustFind(id, auth, tx);
      if (entry.status === 'REMOVED') throw apiError(404, 'LOCKER_NOT_FOUND', 'Bottle not found');

      const data: Prisma.BottleLockerEntryUncheckedUpdateInput = {};
      if (dto.guestName !== undefined) data.guestName = dto.guestName.trim();
      if (dto.mobile !== undefined) data.mobile = dto.mobile || null;
      if (dto.expiresAt !== undefined) data.expiresAt = toDateOnly(dto.expiresAt);
      if (dto.note !== undefined) data.note = dto.note || null;

      if (dto.remainingMl !== undefined && dto.remainingMl !== entry.remainingMl) {
        if (dto.remainingMl > entry.bottleMl) {
          throw apiError(400, 'INVALID_ML', 'Remaining ml cannot be more than the bottle size', {
            bottleMl: entry.bottleMl,
            remainingMl: dto.remainingMl,
          });
        }
        await this.repo.addEvent(tx, {
          entryId: entry.id,
          kind: 'ADJUST',
          ml: dto.remainingMl - entry.remainingMl,
          byId: auth.userId,
          note: dto.note ?? 'Adjusted',
        });
        data.remainingMl = dto.remainingMl;
        data.status = dto.remainingMl === 0 ? 'FINISHED' : entry.status === 'FINISHED' ? 'ACTIVE' : entry.status;
      }
      return this.repo.updateEntry(tx, entry.id, data);
    });
    return this.viewOf(row, today);
  }

  /** Takes the bottle off the locker (REMOVED). The remaining volume is written to the REMOVE event. */
  async remove(id: string, dto: RemoveLockerDto, auth: AuthUser): Promise<LockerView> {
    const today = await this.today(auth.outletId);
    const row = await this.repo.transaction(async (tx) => {
      const entry = await this.mustFind(id, auth, tx);
      if (entry.status === 'REMOVED') throw apiError(404, 'LOCKER_NOT_FOUND', 'Bottle not found');
      await this.repo.addEvent(tx, {
        entryId: entry.id,
        kind: 'REMOVE',
        ml: entry.remainingMl,
        byId: auth.userId,
        note: dto.reason,
      });
      return this.repo.updateEntry(tx, entry.id, { status: 'REMOVED' });
    });
    return this.viewOf(row, today);
  }

  // ---------------------------------------------------------------------------

  private async mustFind(id: string, auth: AuthUser, tx: Prisma.TransactionClient): Promise<LockerRow> {
    const entry = await this.repo.findEntry(id, auth.outletId, tx);
    if (!entry) throw apiError(404, 'LOCKER_NOT_FOUND', 'Bottle not found');
    return entry;
  }

  private isExpired(entry: LockerRow, today: string): boolean {
    return entry.expiresAt.toISOString().slice(0, 10) < today;
  }

  private async today(outletId: string): Promise<string> {
    const tz = await this.ordersRepo.getOutletTimezone(outletId);
    return businessDateFor(new Date(), tz, '05:00');
  }

  private async viewOf(row: LockerRow, today: string): Promise<LockerView> {
    const names = await this.repo.userNames(row.events.map((e) => e.byId));
    return toLockerView(row, today, names);
  }
}
