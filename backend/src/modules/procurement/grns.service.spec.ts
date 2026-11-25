import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { GrnsService } from './grns.service';

const D = (v: number | string) => new Prisma.Decimal(v);

/** Jest mock of a repository: every method exists and returns undefined unless a test sets it. */
function autoMock(overrides: Record<string, unknown> = {}): any {
  const store: Record<string, unknown> = { ...overrides };
  return new Proxy(store, {
    get(target, prop) {
      if (typeof prop === 'symbol') return undefined;
      if (!(prop in target)) target[prop] = jest.fn();
      return target[prop];
    },
  });
}

const auth = { userId: 'u1', tenantId: 't1', outletId: 'o1', personaId: 'p', personaKey: 'storekeeper', role: 'USER', permissions: {}, username: 'sk', } as unknown as AuthUser;

const items: Record<string, any> = {
  'i-lager': { id: 'i-lager', name: 'Premium Lager 650 ml', isLiquor: true, baseUnit: 'ML', packSize: D(650), packName: 'btl', purchaseUnitName: 'Case of 12', purchaseUnitQty: D(7800), avgCost: D(0), isActive: true },
  'i-keg': { id: 'i-keg', name: 'Wheat beer keg 30 L', isLiquor: true, baseUnit: 'ML', packSize: D(30000), packName: 'keg', purchaseUnitName: 'Keg', purchaseUnitQty: D(30000), avgCost: D(0), isActive: true },
  'i-stout': { id: 'i-stout', name: 'Stout 500 ml', isLiquor: true, baseUnit: 'ML', packSize: D(500), packName: 'btl', purchaseUnitName: 'Case of 12', purchaseUnitQty: D(6000), avgCost: D(0), isActive: true },
};

/** PLAN.md 1.7 design example: lager 10 cs (1 damaged at ₹950), keg 4 received and invoiced 5 at ₹7,800, stout 4 cs at ₹4,600. */
function scenario() {
  const state = {
    grn: {
      id: 'g1', tenantId: 't1', outletId: 'o1', number: 'GRN-0091', poId: 'po1', vendorId: 'v1', locationId: 'loc-cellar',
      status: 'DRAFT', vendorInvoiceNo: 'INV-88', invoiceDate: null, receivedOn: new Date('2026-11-25T00:00:00Z'),
      transportPermitNo: 'TP-12', invoicePhotoUrl: null, poValue: D(0), invoiceValue: D(66900), receivedValue: D(0),
      damagedValue: D(0), debitNoteAmount: D(0), payable: D(0), mismatch: false, createdById: 'u1', postedById: null,
      postedAt: null, createdAt: new Date(),
    } as any,
    lines: [
      { id: 'l1', grnId: 'g1', poLineId: 'pl1', stockItemId: 'i-lager', orderedQty: D(10), invoicedQty: D(10), receivedQty: D(10), damagedQty: D(1), rate: D(950), batch: null, expiry: null },
      { id: 'l2', grnId: 'g1', poLineId: 'pl2', stockItemId: 'i-keg', orderedQty: D(4), invoicedQty: D(5), receivedQty: D(4), damagedQty: D(0), rate: D(7800), batch: null, expiry: null },
      { id: 'l3', grnId: 'g1', poLineId: 'pl3', stockItemId: 'i-stout', orderedQty: D(4), invoicedQty: D(4), receivedQty: D(4), damagedQty: D(0), rate: D(4600), batch: null, expiry: null },
    ] as any[],
    po: { id: 'po1', number: 'PO-0317', vendorId: 'v1', locationId: 'loc-cellar', status: 'SENT', total: D(38400) } as any,
    poLines: [
      { id: 'pl1', poId: 'po1', stockItemId: 'i-lager', qty: D(10), rate: D(950), receivedQty: D(0), sortOrder: 0 },
      { id: 'pl2', poId: 'po1', stockItemId: 'i-keg', qty: D(4), rate: D(7800), receivedQty: D(0), sortOrder: 1 },
      { id: 'pl3', poId: 'po1', stockItemId: 'i-stout', qty: D(4), rate: D(4600), receivedQty: D(0), sortOrder: 2 },
    ] as any[],
    debitNotes: [] as any[],
    wastage: [] as any[],
  };

  const repo = autoMock({
    transaction: jest.fn(async (fn: (tx: unknown) => unknown) => fn({})),
    outletTimezone: jest.fn(async () => 'Asia/Kolkata'),
    findGoodsReceipt: jest.fn(async () => state.grn),
    grnLines: jest.fn(async () => state.lines),
    findItemsByIds: jest.fn(async (ids: string[]) => ids.map((id) => items[id]).filter(Boolean)),
    findPurchaseOrder: jest.fn(async () => state.po),
    poLines: jest.fn(async () => state.poLines),
    poLinesIn: jest.fn(async () => state.poLines),
    addPoLineReceived: jest.fn(async (_tx: unknown, poLineId: string, qty: Prisma.Decimal) => {
      const l = state.poLines.find((x) => x.id === poLineId)!;
      l.receivedQty = l.receivedQty.plus(qty);
    }),
    updatePurchaseOrder: jest.fn(async (_tx: unknown, _id: string, data: any) => {
      state.po = { ...state.po, ...data };
    }),
    updateItemRate: jest.fn(async () => undefined),
    claimDraftGrn: jest.fn(async () => 1),
    createGoodsReceipt: jest.fn(async (_tx: unknown, data: any) => ({ id: 'g2', createdAt: new Date(), ...data })),
    createGrnLines: jest.fn(async () => undefined),
    createWastage: jest.fn(async (_tx: unknown, data: any) => {
      state.wastage.push(data);
      return { id: `w${state.wastage.length}`, ...data };
    }),
    createDebitNote: jest.fn(async (_tx: unknown, data: any) => {
      state.debitNotes.push(data);
      return data;
    }),
    updateGoodsReceipt: jest.fn(async (_tx: unknown, _id: string, data: any) => {
      state.grn = { ...state.grn, ...data };
    }),
    findVendorsByIds: jest.fn(async () => [{ id: 'v1', name: 'City Breweries Supply' }]),
    findLocationsByIds: jest.fn(async () => [{ id: 'loc-cellar', name: 'Cellar' }]),
    posByIds: jest.fn(async () => [{ id: 'po1', number: 'PO-0317' }]),
    findVendor: jest.fn(async () => ({ id: 'v1' })),
    grnsForPurchaseOrder: jest.fn(async () => [state.grn]),
  });
  const ledger = autoMock({
    post: jest.fn(async (_tx: unknown, _ctx: unknown, inputs: unknown[]) => inputs),
    onHand: jest.fn(async () => D(0)),
  });
  const docs = autoMock({ next: jest.fn(async () => 1) });
  const realtime = autoMock({ publish: jest.fn() });
  const service = new GrnsService(repo, docs, ledger, realtime);
  return { state, repo, ledger, docs, realtime, service };
}

async function codeOf(p: Promise<unknown>): Promise<{ code: string; details?: any }> {
  try {
    await p;
  } catch (e) {
    return (e as HttpException).getResponse() as { code: string; details?: any };
  }
  throw new Error('expected an error');
}

describe('GrnsService.post (PLAN.md 1.7 design example)', () => {
  it('receives the lines at the invoice rate per base unit', async () => {
    const { service, ledger } = scenario();
    await service.post('g1', auth);
    const receipts = ledger.post.mock.calls[0][2] as any[];
    expect(receipts.map((r) => r.type)).toEqual(['RECEIPT', 'RECEIPT', 'RECEIPT']);
    expect(receipts.map((r) => r.qty.toFixed(3))).toEqual(['78000.000', '120000.000', '24000.000']);
    expect(receipts[0].unitCost.toFixed(6)).toBe('0.121795');
  });

  it('writes the damaged case off as ₹950 wastage', async () => {
    const { service, state } = scenario();
    await service.post('g1', auth);
    expect(state.wastage).toHaveLength(1);
    expect(state.wastage[0].reason).toBe('DAMAGED_DELIVERY');
    expect(state.wastage[0].value.toFixed(2)).toBe('950.00');
    expect(state.wastage[0].qty.toFixed(3)).toBe('7800.000');
  });

  it('raises a ₹7,800 debit note for the keg invoiced but not received', async () => {
    const { service, state } = scenario();
    await service.post('g1', auth);
    expect(state.debitNotes).toHaveLength(1);
    expect(state.debitNotes[0].amount.toFixed(2)).toBe('7800.00');
    expect(state.debitNotes[0].reason).toBe('1 × Wheat beer keg 30 L invoiced, not received');
  });

  it('posts the GRN with payable ₹59,100 and the PO as INVOICE_MISMATCH', async () => {
    const { service, state, repo } = scenario();
    const posted = await service.post('g1', auth);
    expect(state.grn.status).toBe('POSTED');
    expect(state.grn.payable.toFixed(2)).toBe('59100.00');
    expect(repo.updatePurchaseOrder).toHaveBeenCalledWith(expect.anything(), 'po1', { status: 'INVOICE_MISMATCH' });
    expect(posted.status).toBe('POSTED');
    expect(posted.preview.payable).toBe('59100.00');
  });

  it('adds received quantities to the PO lines', async () => {
    const { service, state } = scenario();
    await service.post('g1', auth);
    expect(state.poLines.map((l) => l.receivedQty.toFixed(3))).toEqual(['10.000', '4.000', '4.000']);
  });

  it('stores the last purchase rate on items that were received', async () => {
    const { service, repo } = scenario();
    await service.post('g1', auth);
    expect(repo.updateItemRate).toHaveBeenCalledTimes(3);
  });
});

describe('GrnsService.post refusals', () => {
  it('needs an invoice number', async () => {
    const s = scenario();
    s.state.grn.vendorInvoiceNo = null;
    expect((await codeOf(s.service.post('g1', auth))).code).toBe('INVOICE_NO_REQUIRED');
  });

  it('needs a transport permit when liquor is received', async () => {
    const s = scenario();
    s.state.grn.transportPermitNo = null;
    expect((await codeOf(s.service.post('g1', auth))).code).toBe('PERMIT_REQUIRED');
  });

  it('refuses a receipt that is already posted', async () => {
    const s = scenario();
    s.state.grn.status = 'POSTED';
    expect((await codeOf(s.service.post('g1', auth))).code).toBe('GRN_POSTED');
  });

  it('refuses goods against a PO that is not receivable', async () => {
    const s = scenario();
    s.state.po.status = 'RECEIVED';
    expect((await codeOf(s.service.post('g1', auth))).code).toBe('PO_NOT_RECEIVABLE');
  });

  it('refuses damaged goods above the received quantity with the line and field', async () => {
    const s = scenario();
    s.state.lines[0].damagedQty = D(11);
    const err = await codeOf(s.service.post('g1', auth));
    expect(err.code).toBe('INVALID_QTY');
    expect(err.details).toEqual({ line: 0, field: 'damagedQty' });
  });
});

describe('GrnsService.create with a PO', () => {
  it('pre-fills the lines from the outstanding PO quantities', async () => {
    const s = scenario();
    s.state.poLines[0].receivedQty = D(0);
    await s.service.create({ poId: 'po1' } as any, auth);
    const rows = s.repo.createGrnLines.mock.calls[0][1] as any[];
    expect(rows.map((r) => r.orderedQty.toFixed(3))).toEqual(['10.000', '4.000', '4.000']);
    expect(rows.map((r) => r.invoicedQty.toFixed(3))).toEqual(['10.000', '4.000', '4.000']);
    expect(rows.every((r) => r.damagedQty.isZero())).toBe(true);
    expect(rows[0].poLineId).toBe('pl1');
  });
});
