import { Prisma } from '@prisma/client';
import { computeDayTotals, DayFacts } from './day-totals';

const D = (v: number | string) => new Prisma.Decimal(v);

describe('computeDayTotals', () => {
  const facts: DayFacts = {
    businessDate: '2026-11-25',
    orders: [
      {
        id: 'paid', status: 'CLOSED', type: 'DINE_IN', subtotal: D(100), discountTotal: D(0), serviceCharge: D(0),
        roundOff: D(0), grandTotal: D(105), taxBreakdown: [
          { name: 'CGST', rate: '2.50', amount: '2.50' },
          { name: 'SGST', rate: '2.50', amount: '2.50' },
        ],
      },
      { id: 'void', status: 'VOID', type: 'DINE_IN', subtotal: D(50), discountTotal: D(0), serviceCharge: D(0), roundOff: D(0), grandTotal: D(50), taxBreakdown: [] },
      { id: 'open', status: 'SENT', type: 'DINE_IN', subtotal: D(30), discountTotal: D(0), serviceCharge: D(0), roundOff: D(0), grandTotal: D(30), taxBreakdown: [] },
    ],
    payments: [
      { orderId: 'paid', paymentMethod: 'CASH', amount: D(105), tipAmount: D(5), status: 'PAID' },
      { orderId: 'paid', paymentMethod: 'CASH', amount: D(-20), tipAmount: D(0), status: 'REFUNDED' },
    ],
    items: [{ orderId: 'paid', productId: 'p1', quantity: 2, net: D(100), status: 'NEW' }],
    discounts: [],
    categoryOfProduct: new Map([['p1', 'c1']]),
    categoryNames: new Map([['c1', 'Mains']]),
    userNames: new Map(),
  };

  it('counts orders and sums only orders that took money', () => {
    const t = computeDayTotals(facts);
    expect(t.orders).toEqual({ count: 3, paid: 1, void: 1, open: 1 });
    expect(t.net).toBe('105.00');
    expect(t.voids).toEqual({ count: 1, amount: '50.00' });
  });

  it('keeps tax per component and cash expected including tips and refunds', () => {
    const t = computeDayTotals(facts);
    expect(t.tax.map((x) => [x.name, x.amount])).toEqual([
      ['CGST', '2.50'],
      ['SGST', '2.50'],
    ]);
    expect(t.cashExpected).toBe('90.00');
    expect(t.refunds).toEqual({ count: 1, amount: '20.00' });
    expect(t.byCategory).toEqual([{ categoryId: 'c1', name: 'Mains', quantity: 2, amount: '100.00' }]);
  });
});
