import { Injectable } from '@nestjs/common';
import { DebitNote, Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { money2, ymd } from '../inventory/inventory-views';
import { DebitNotesQueryDto } from './dto/procurement.dto';
import { ProcurementRepository } from './procurement.repository';

/** Debit notes raised by GRN posts (PLAN.md 1.7). Settling one only changes its status. */
@Injectable()
export class DebitNotesService {
  constructor(private repo: ProcurementRepository) {}

  async list(q: DebitNotesQueryDto, auth: AuthUser) {
    const notes = await this.repo.listDebitNotes(auth.outletId, q.status ? { status: q.status } : {});
    return this.views(notes);
  }

  async settle(id: string, auth: AuthUser) {
    const note = await this.repo.findDebitNote(auth.outletId, id);
    if (!note) throw apiError(404, 'DEBIT_NOTE_NOT_FOUND', 'Debit note not found');
    if (note.status !== 'OPEN') throw apiError(409, 'DEBIT_NOTE_NOT_OPEN', 'This debit note is not open');
    await this.repo.transaction(async (tx) => this.repo.settleDebitNote(tx, id));
    const [view] = await this.views([{ ...note, status: 'SETTLED' }]);
    return view;
  }

  private async views(notes: DebitNote[]) {
    if (notes.length === 0) return [];
    const vendors = await this.repo.findVendorsByIds([...new Set(notes.map((n) => n.vendorId))]);
    const grnIds = [...new Set(notes.map((n) => n.grnId).filter((v): v is string => !!v))];
    const grns = grnIds.length ? await this.repo.grnsByIds(grnIds) : [];
    const vendorName = new Map(vendors.map((v) => [v.id, v.name]));
    const grnNumber = new Map(grns.map((g) => [g.id, g.number]));
    return notes.map((n) => ({
      id: n.id,
      number: n.number,
      vendor: { id: n.vendorId, name: vendorName.get(n.vendorId) ?? null },
      grnNumber: n.grnId ? (grnNumber.get(n.grnId) ?? null) : null,
      amount: money2(n.amount as Prisma.Decimal),
      reason: n.reason,
      status: n.status,
      createdAt: n.createdAt.toISOString(),
      date: ymd(n.createdAt),
    }));
  }
}
