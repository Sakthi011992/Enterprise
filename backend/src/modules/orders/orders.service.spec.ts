import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { OrdersService } from './orders.service';
import { OrderPricingService } from './order-pricing.service';
import { AuthUser } from '../../common/decorators/current-user.decorator';

const D = (v: number | string) => new Prisma.Decimal(v);
const codeOf = (e: unknown) => (e as HttpException).getResponse() as { code: string };

const taxSnap = (isLiquor: boolean) => ({
  snapshot: {
    taxClassId: isLiquor ? 'vat' : 'gst5',
    code: isLiquor ? 'VAT_LIQUOR' : 'GST5',
    name: 'Tax',
    rate: isLiquor ? '20.00' : '5.00',
    inclusive: false,
    isLiquor,
    components: isLiquor ? [{ name: 'VAT', rate: 20 }] : [{ name: 'CGST', rate: 2.5 }, { name: 'SGST', rate: 2.5 }],
  },
  components: [],
});

function item(id: string, o: { productId: string; price: number; status?: string; isLiquor?: boolean; seat?: number }) {
  return {
    id,
    orderId: 'ord1',
    productId: o.productId,
    productName: id,
    variantName: null,
    variantId: null,
    comboId: null,
    price: D(o.price),
    quantity: 1,
    taxPercentage: D(5),
    taxAmount: D(0),
    lineTotal: D(0),
    grossAmount: D(0),
    discountAmount: D(0),
    seat: o.seat ?? null,
    status: o.status ?? 'NEW',
    modifiers: [],
    note: null,
    happyHourPercent: null,
    taxClassId: null,
    taxBreakdown: taxSnap(!!o.isLiquor),
    sentAt: null,
    voidedAt: null,
    voidReason: null,
    createdById: 'u1',
  };
}

/** A small in-memory order. Repository writes update it, so later reads see them. */
function fixture(items: ReturnType<typeof item>[], status = 'SENT') {
  return {
    order: {
      id: 'ord1', outletId: 'o1', tenantId: 't1', orderNumber: 'A-1', invoiceNumber: null, type: 'TAKEAWAY', status,
      tableId: null, covers: 1, waiterId: null, cashierId: 'u1', subtotal: D(0), discountTotal: D(0), serviceCharge: D(0),
      taxAmount: D(0), tipTotal: D(0), roundOff: D(0), grandTotal: D(0), taxBreakdown: [], note: null, offlineId: null,
      heldAt: null, billedAt: null, paidAt: null, closedAt: null, voidedAt: null, voidReason: null, dayCloseId: null,
      createdAt: new Date(), updatedAt: new Date(),
    },
    items,
    discounts: [] as any[],
    payments: [] as any[],
  };
}

const auth = (over: Partial<AuthUser> = {}): AuthUser =>
  ({
    userId: 'u1', username: 'cashier', tenantId: 't1', outletId: 'o1', personaId: 'p1', personaKey: 'cashier', role: 'USER',
    permissions: {
      'sales.discount.give': { level: 'LIMITED', limit: 10 },
      'sales.void': { level: 'REQUEST', limit: null },
    },
    ...over,
  }) as AuthUser;

function build(fx: ReturnType<typeof fixture>, extra: { check?: boolean } = {}) {
  const repo: any = {
    transaction: (fn: (tx: unknown) => unknown) => fn({}),
    loadBundle: jest.fn(async () => fx),
    getOutletSettings: jest.fn(async () => ({
      serviceChargePercent: D(0), serviceChargeTypes: ['DINE_IN'], roundingMode: 'NONE', orderPrefix: 'A',
      invoicePrefix: 'INV', countryCode: 'IN',
    })),
    updateItem: jest.fn(async (_tx: unknown, id: string, data: any) => Object.assign(fx.items.find((i) => i.id === id)!, data)),
    updateDiscount: jest.fn(async () => ({})),
    updateOrder: jest.fn(async (_tx: unknown, _id: string, data: any) => Object.assign(fx.order, data)),
    createDiscount: jest.fn(async (_tx: unknown, data: any) => {
      const row = { id: 'd1', createdAt: new Date(), ...data };
      fx.discounts.push(row);
      return row;
    }),
    viewContext: jest.fn(async () => ({ routing: new Map(), table: null, waiter: null, userNames: new Map() })),
    routingFor: jest.fn(async () => new Map([
      ['pWings', { station: 'KITCHEN', ticketKind: 'KOT' }],
      ['pLager', { station: 'BAR', ticketKind: 'BOT' }],
    ])),
    countTicketsSince: jest.fn(async () => 0),
    createTicket: jest.fn(async (_tx: unknown, data: any) => ({ id: `t${data.seq}`, createdAt: new Date(), printedAt: null, status: 'QUEUED', ...data })),
    getOutletTimezone: jest.fn(async () => 'Asia/Kolkata'),
    deleteItem: jest.fn(),
    findTable: jest.fn(),
    findOriginalTickets: jest.fn(async () => []),
  };
  const pricing = new OrderPricingService(repo);
  const approvals: any = { assertApproved: jest.fn(async () => ({ approverId: 'm1' })) };
  const audit: any = { record: jest.fn() };
  const permissions: any = { check: jest.fn(() => extra.check ?? false) };
  const print: any = { queueTicket: jest.fn(async () => null), queueBill: jest.fn() };
  const stock: any = {
    deductForSentItems: jest.fn(async () => ({ eightySixed: [] })),
    reverseSale: jest.fn(async () => undefined),
  };
  const realtime: any = { publish: jest.fn() };
  const tabs: any = { enforce: jest.fn(async () => []) };
  const svc = new OrdersService(repo, pricing, {} as any, approvals, audit, permissions, print, stock, realtime, tabs);
  return { svc, repo, approvals, audit, permissions, print, stock, realtime, tabs };
}

describe('OrdersService', () => {
  it('send groups new lines into one ticket per station and marks them SENT', async () => {
    const fx = fixture([item('w', { productId: 'pWings', price: 350 }), item('l', { productId: 'pLager', price: 300 })], 'OPEN');
    const { svc, repo, print } = build(fx);

    const res = await svc.send('ord1', auth());

    expect(res.tickets.map((t) => [t.station, t.kind, t.seq])).toEqual([
      ['KITCHEN', 'KOT', 1],
      ['BAR', 'BOT', 2],
    ]);
    expect(fx.items.every((i) => i.status === 'SENT')).toBe(true);
    expect(fx.order.status).toBe('SENT');
    expect(repo.createTicket).toHaveBeenCalledTimes(2);
    expect(print.queueTicket).toHaveBeenCalledTimes(2);
  });

  it('refuses a line-level discount above the LIMITED limit without an approval', async () => {
    const fx = fixture([item('w', { productId: 'pWings', price: 100, status: 'SENT' })]);
    const { svc, repo } = build(fx);

    const err = await svc
      .addDiscount('ord1', { type: 'PERCENT', value: 20, reason: 'Friend', itemIds: [] }, auth())
      .catch((e) => e);

    expect(err).toBeInstanceOf(HttpException);
    expect(codeOf(err).code).toBe('APPROVAL_REQUIRED');
    expect(repo.createDiscount).not.toHaveBeenCalled();
  });

  it('applies the same discount with a matching approval and records the approver', async () => {
    const fx = fixture([item('w', { productId: 'pWings', price: 100, status: 'SENT' })]);
    const { svc, repo, approvals } = build(fx);

    await svc.addDiscount(
      'ord1',
      { type: 'PERCENT', value: 20, reason: 'Friend', itemIds: [], approvalId: 'a1' },
      auth(),
    );

    expect(approvals.assertApproved).toHaveBeenCalledWith(
      'a1',
      expect.anything(),
      'DISCOUNT',
      { type: 'PERCENT', value: 20, itemIds: [], reason: 'Friend' },
      'ord1',
    );
    expect(repo.createDiscount).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ approvedById: 'm1' }));
  });

  it('refuses an item-level discount on a liquor line (engine error passed through)', async () => {
    const fx = fixture([item('s', { productId: 'pMalt', price: 500, status: 'SENT', isLiquor: true })]);
    const { svc } = build(fx, { check: true });

    const err = await svc
      .addDiscount('ord1', { type: 'PERCENT', value: 10, reason: 'Manager', itemIds: ['s'] }, auth({
        permissions: { 'sales.discount.give': { level: 'EDIT', limit: null } } as any,
      }))
      .catch((e) => e);

    expect(codeOf(err).code).toBe('LIQUOR_DISCOUNT_NOT_ALLOWED');
  });

  it('voiding a sent line prints a cancellation ticket and logs wastage', async () => {
    const fx = fixture([item('w', { productId: 'pWings', price: 350, status: 'SENT' })]);
    const { svc, repo, audit, print } = build(fx, { check: true });

    await svc.voidItems('ord1', { itemIds: ['w'], reason: 'Dropped' }, auth());

    expect(repo.createTicket).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ isCancellation: true, station: 'KITCHEN' }));
    expect(audit.record).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ action: 'wastage' }));
    expect(print.queueTicket).toHaveBeenCalledWith(expect.objectContaining({ isCancellation: true }));
    expect(fx.items[0].status).toBe('VOIDED');
  });

  it('send deducts recipes at each line\'s station and publishes one KDS card per ticket after commit', async () => {
    const fx = fixture([item('w', { productId: 'pWings', price: 350 }), item('l', { productId: 'pLager', price: 300 })], 'OPEN');
    const { svc, stock, realtime, print } = build(fx);

    await svc.send('ord1', auth());

    expect(stock.deductForSentItems).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ tenantId: 't1', outletId: 'o1', userId: 'u1', events: expect.any(Array) }),
      expect.any(Array),
    );
    const items = stock.deductForSentItems.mock.calls[0][2];
    expect(items.map((i: any) => [i.orderItemId, i.station])).toEqual([
      ['w', 'KITCHEN'],
      ['l', 'BAR'],
    ]);
    const events = realtime.publish.mock.calls[0][0];
    expect(events.filter((e: any) => e.event === 'kds.ticket.created').map((e: any) => e.station)).toEqual(['KITCHEN', 'BAR']);
    expect(events.find((e: any) => e.event === 'order.updated')).toBeDefined();
    expect(print.queueTicket).toHaveBeenCalledTimes(2);
  });

  it('voiding a sent line reverses its sale and re-sends the original ticket', async () => {
    const fx = fixture([item('w', { productId: 'pWings', price: 350, status: 'SENT' })]);
    const { svc, repo, stock, realtime } = build(fx, { check: true });
    repo.findOriginalTickets.mockResolvedValueOnce([
      { id: 'orig', kind: 'KOT', station: 'KITCHEN', seq: 1, kdsStatus: 'NEW', createdAt: new Date(), readyAt: null, items: [{ orderItemId: 'w', name: 'Wings', quantity: 1 }] },
    ]);

    await svc.voidItems('ord1', { itemIds: ['w'], reason: 'Dropped' }, auth());

    expect(stock.reverseSale).toHaveBeenCalledWith(expect.anything(), expect.anything(), ['w'], 'Dropped');
    const events = realtime.publish.mock.calls[0][0];
    const updated = events.find((e: any) => e.event === 'kds.ticket.updated');
    expect(updated.payload.items[0]).toMatchObject({ orderItemId: 'w', voided: true });
    expect(events.some((e: any) => e.event === 'kds.ticket.created')).toBe(false);
  });

  it('voiding without APPROVE needs an approval', async () => {
    const fx = fixture([item('w', { productId: 'pWings', price: 350, status: 'SENT' })]);
    const { svc } = build(fx, { check: false });

    const err = await svc.voidItems('ord1', { itemIds: ['w'], reason: 'Dropped' }, auth()).catch((e) => e);
    expect(codeOf(err).code).toBe('APPROVAL_REQUIRED');
  });
});
