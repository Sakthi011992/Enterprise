import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PaymentsService } from './payments.service';
import { AuthUser } from '../../common/decorators/current-user.decorator';

const D = (v: number | string) => new Prisma.Decimal(v);
const codeOf = (e: unknown) => (e as HttpException).getResponse() as { code: string };

const auth = { userId: 'u1', tenantId: 't1', outletId: 'o1', permissions: {} } as unknown as AuthUser;

function fixture(grand: number, invoiceNumber: string | null = null) {
  return {
    order: {
      id: 'ord1', outletId: 'o1', status: 'SENT', type: 'DINE_IN', tableId: 'tb1', invoiceNumber,
      subtotal: D(grand), taxAmount: D(0), grandTotal: D(grand), discountTotal: D(0), serviceCharge: D(0),
      roundOff: D(0), tipTotal: D(0), taxBreakdown: [], covers: 2, waiterId: null, heldAt: null, billedAt: null,
      paidAt: null, closedAt: null, voidedAt: null, voidReason: null, note: null, createdAt: new Date(), orderNumber: 'A-1',
    },
    items: [],
    discounts: [],
    payments: [] as any[],
  };
}

function build(grand: number, invoiceNumber: string | null = null) {
  const fx = fixture(grand, invoiceNumber);
  const repo: any = {
    transaction: (fn: (tx: unknown) => unknown) => fn({}),
    createPayment: jest.fn(async (_tx: unknown, data: any) => {
      const row = { id: `p${fx.payments.length + 1}`, createdAt: new Date(), status: 'PAID', ...data };
      fx.payments.push(row);
      return row;
    }),
    findPayment: jest.fn(),
    markRefunded: jest.fn(),
  };
  const orders: any = {
    loadBundle: jest.fn(async () => fx),
    updateOrder: jest.fn(async (_tx: unknown, _id: string, data: any) => Object.assign(fx.order, data)),
    setTableStatus: jest.fn(),
    getOutletSettings: jest.fn(async () => ({ countryCode: 'IN', invoicePrefix: 'INV' })),
    viewContext: jest.fn(async () => ({ routing: new Map(), table: null, waiter: null, userNames: new Map() })),
  };
  const pricing: any = { recalc: jest.fn(async () => fx) };
  const invoices: any = { issueForOrder: jest.fn(async () => 'INV/2026-27/000001') };
  const print: any = { openDrawer: jest.fn(async () => null) };
  const svc = new PaymentsService(repo, orders, pricing, invoices, {} as any, { record: jest.fn() } as any, { check: jest.fn(() => false) } as any, print, { onOrderPaid: jest.fn() } as any, { publish: jest.fn() } as any);
  return { svc, fx, orders, invoices, print };
}

describe('PaymentsService.pay', () => {
  it('gives cash change after the bill and the tip, and keeps the order open while part-paid', async () => {
    const { svc, fx, invoices, print } = build(300);

    const res = await svc.pay('ord1', {
      payments: [{ method: 'CASH' as any, amount: 250, tendered: 500 }],
      tipAmount: 25,
    }, auth);

    expect(res.change).toBe('225.00');
    expect(fx.payments[0].tipAmount.toFixed(2)).toBe('25.00');
    expect(fx.payments[0].changeGiven.toFixed(2)).toBe('225.00');
    expect(invoices.issueForOrder).not.toHaveBeenCalled();
    expect(fx.order.status).toBe('SENT');
    expect(print.openDrawer).toHaveBeenCalled();
  });

  it('refuses a payment above the balance due', async () => {
    const { svc, fx } = build(300);

    const err = await svc.pay('ord1', { payments: [{ method: 'CARD' as any, amount: 350 }] }, auth).catch((e) => e);

    expect(err).toBeInstanceOf(HttpException);
    expect(codeOf(err).code).toBe('PAYMENT_EXCEEDS_DUE');
    expect(codeOf(err)).toMatchObject({ code: 'PAYMENT_EXCEEDS_DUE' });
    expect(fx.payments).toHaveLength(0);
  });

  it('splits tender across lines and settles on full payment, allocating the invoice number once', async () => {
    const { svc, fx, invoices, orders } = build(300);

    await svc.pay('ord1', {
      payments: [
        { method: 'UPI' as any, amount: 100, reference: 'UTR123' },
        { method: 'CARD' as any, amount: 200 },
      ],
    }, auth);

    expect(fx.order.status).toBe('PAID');
    expect(fx.order.invoiceNumber).toBe('INV/2026-27/000001');
    expect(invoices.issueForOrder).toHaveBeenCalledTimes(1);
    expect(orders.setTableStatus).toHaveBeenCalledWith(expect.anything(), 'tb1', 'CLEANING');
  });

  it('does not allocate a second invoice number for an order that already has one', async () => {
    const { svc, invoices } = build(300, 'INV/2026-27/000007');

    await svc.pay('ord1', { payments: [{ method: 'CARD' as any, amount: 300 }] }, auth);

    expect(invoices.issueForOrder).not.toHaveBeenCalled();
  });

  it('refuses cash handed over short of the amount owed', async () => {
    const { svc } = build(300);

    const err = await svc
      .pay('ord1', { payments: [{ method: 'CASH' as any, amount: 300, tendered: 200 }] }, auth)
      .catch((e) => e);

    expect(codeOf(err).code).toBe('TENDERED_TOO_LOW');
  });
});
