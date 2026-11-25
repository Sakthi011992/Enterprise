import { columnsFor, formatAmount, formatOutletTime, renderBill, renderReport, renderTicket, twoColumn, wrap } from './print-renderer';

const PRINTED = '25 Nov 2026, 18:40';

describe('print renderer', () => {
  it('uses 32 columns for 58 mm paper and 48 for 80 mm', () => {
    expect(columnsFor(58)).toBe(32);
    expect(columnsFor(80)).toBe(48);
  });

  it('formats amounts with two decimals and thousands separators', () => {
    expect(formatAmount('1234.5')).toBe('1,234.50');
    expect(formatAmount(0)).toBe('0.00');
    expect(formatAmount('-1000')).toBe('-1,000.00');
    expect(formatAmount('12345678.9')).toBe('12,345,678.90');
  });

  it('pads two columns to the full paper width', () => {
    const line = twoColumn('Subtotal', '1,000.00', 32);
    expect(line).toHaveLength(32);
    expect(line.endsWith('1,000.00')).toBe(true);
    expect(line.startsWith('Subtotal')).toBe(true);
  });

  it('truncates a long left column instead of overflowing the line', () => {
    const line = twoColumn('x'.repeat(60), '1.00', 32);
    expect(line).toHaveLength(32);
    expect(line.endsWith(' 1.00')).toBe(true);
  });

  it('word-wraps text and splits words longer than the width', () => {
    expect(wrap('aaa bbb ccc', 7)).toEqual(['aaa bbb', 'ccc']);
    expect(wrap('abcdefghij', 4)).toEqual(['abcd', 'efgh', 'ij']);
    expect(wrap('', 10)).toEqual(['']);
  });

  it('formats times in the outlet time zone', () => {
    // 13:10 UTC is 18:40 in Asia/Kolkata (UTC+5:30).
    expect(formatOutletTime(new Date('2026-11-25T13:10:00Z'), 'Asia/Kolkata')).toBe(PRINTED);
  });

  it('renders a bill whose totals block adds up and fits the paper', () => {
    const payload = renderBill(
      {
        outletName: 'Riverside Bar',
        orderNumber: 'A-1043',
        invoiceNumber: null,
        orderType: 'DINE_IN',
        tableName: 'R4',
        staffName: 'Priya',
        printedAt: PRINTED,
        items: [
          { quantity: 2, name: 'Premium Lager 650 ml', unitPrice: '300.00', gross: '600.00', modifiers: [] },
          { quantity: 1, name: 'Chicken Wings (8 pc)', unitPrice: '350.00', gross: '350.00', modifiers: [] },
          { quantity: 1, name: 'House Whisky', variantName: '60 ml', unitPrice: '340.00', gross: '340.00', modifiers: ['On the rocks'] },
        ],
        subtotal: '1290.00',
        discountTotal: '0',
        serviceCharge: '64.50',
        taxBreakdown: [
          { name: 'CGST', rate: 2.5, amount: '32.26' },
          { name: 'SGST', rate: 2.5, amount: '32.26' },
        ],
        roundOff: '0.48',
        grandTotal: '1419.00',
      },
      80,
    );
    const texts = payload.lines.map((l) => l.text);
    expect(texts.every((t) => t.length <= 48)).toBe(true);
    expect(texts).toContain(twoColumn('Subtotal', '1,290.00', 48));
    expect(texts).toContain(twoColumn('Service charge', '64.50', 48));
    expect(texts).toContain(twoColumn('CGST @ 2.5%', '32.26', 48));
    expect(texts).toContain(twoColumn('TOTAL', '1,419.00', 48));
    expect(texts).toContain('   + On the rocks');
    expect(payload.cut).toBe(true);
  });

  it('omits the discount line when there is no discount and shows it when there is', () => {
    const base = {
      outletName: 'Riverside Bar',
      orderNumber: 'A-1',
      orderType: 'TAKEAWAY',
      tableName: null,
      staffName: null,
      printedAt: PRINTED,
      items: [],
      subtotal: '100.00',
      serviceCharge: '0',
      taxBreakdown: [],
      roundOff: '0',
      grandTotal: '100.00',
    };
    const none = renderBill({ ...base, discountTotal: '0' }, 58).lines.map((l) => l.text.trim());
    expect(none.some((t) => t.startsWith('Discount'))).toBe(false);
    const some = renderBill({ ...base, discountTotal: '30.00' }, 58).lines.map((l) => l.text);
    expect(some).toContain(twoColumn('Discount', '-30.00', 32));
  });

  it('renders a ticket with seats, modifiers and notes inside the paper width', () => {
    const payload = renderTicket(
      {
        kind: 'BOT',
        seq: 7,
        station: 'BAR',
        isCancellation: false,
        outletName: 'Riverside Bar',
        orderNumber: 'A-1043',
        orderType: 'DINE_IN',
        tableName: 'R4',
        staffName: 'Priya',
        printedAt: PRINTED,
        items: [
          { quantity: 1, name: 'Single Malt 12Y', variantName: '60 ml', modifiers: ['On the rocks'], seat: 2, note: null },
          { quantity: 2, name: 'Premium Lager 650 ml', modifiers: [], seat: null, note: 'Chilled glass please, very cold' },
        ],
      },
      58,
    );
    expect(payload.lines[0].text).toBe('BAR BOT #7');
    expect(payload.lines.every((l) => l.text.length <= 32)).toBe(true);
    expect(payload.lines.map((l) => l.text)).toEqual(expect.arrayContaining(['   + On the rocks', '   Seat 2']));
  });

  it('marks cancellation tickets', () => {
    const payload = renderTicket(
      {
        kind: 'KOT',
        seq: 3,
        station: 'KITCHEN',
        isCancellation: true,
        outletName: 'Riverside Bar',
        orderNumber: 'A-9',
        orderType: 'DINE_IN',
        tableName: null,
        staffName: null,
        printedAt: PRINTED,
        items: [{ quantity: 1, name: 'Chicken Wings', modifiers: [] }],
      },
      80,
    );
    expect(payload.lines[0].text).toBe('CANCEL KITCHEN KOT #3');
    expect(payload.lines.map((l) => l.text)).toContain('*** CANCELLED ITEMS ***');
  });

  it('renders a Z report with the cash variance', () => {
    const payload = renderReport(
      {
        kind: 'Z',
        outletName: 'Riverside Bar',
        printedAt: PRINTED,
        cashCounted: '4980.00',
        totals: {
          businessDate: '2026-11-25',
          orders: { count: 12, paid: 11, void: 1, open: 0 },
          gross: '9000.00',
          discounts: '500.00',
          serviceCharge: '400.00',
          tax: [{ name: 'GST', rate: 5, amount: '400.00' }],
          roundOff: '0',
          net: '9300.00',
          tips: '150.00',
          byPayment: [{ method: 'CASH', count: 5, amount: '5000.00' }],
          byType: [{ type: 'DINE_IN', count: 11, amount: '9300.00' }],
          voids: { count: 1, amount: '200.00' },
          refunds: { count: 0, amount: '0' },
          cashExpected: '5000.00',
        },
      },
      48,
    );
    const texts = payload.lines.map((l) => l.text);
    expect(texts).toContain(twoColumn('Expected', '5,000.00', 48));
    expect(texts).toContain(twoColumn('Counted', '4,980.00', 48));
    expect(texts).toContain(twoColumn('Variance', '-20.00', 48));
    expect(payload.lines[0].text).toContain('Z REPORT');
  });
});
