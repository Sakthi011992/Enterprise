import { Prisma } from '@prisma/client';
import { buildShares, SplitLine } from './split';

const D = (v: number | string) => new Prisma.Decimal(v);
const sum = (xs: { amount: Prisma.Decimal }[]) => xs.reduce((s, x) => s.add(x.amount), D(0));

const lines: SplitLine[] = [
  { id: 'a', seat: 1, total: D(118) },
  { id: 'b', seat: 2, total: D(236) },
  { id: 'c', seat: 2, total: D(59) },
];
const grand = D(412.5);
const extra = D(-0.5);

describe('buildShares', () => {
  it('splits equally with the remainder on the last part', () => {
    const shares = buildShares({ mode: 'EQUAL', parts: 3, lines: [], grandTotal: D(1000), extra: D(0), paidBySeat: new Map() });
    expect(shares.map((s) => s.amount.toFixed(2))).toEqual(['333.33', '333.33', '333.34']);
    expect(sum(shares).toFixed(2)).toBe('1000.00');
  });

  it('splits by seat and sums to the grand total including service and round-off', () => {
    const shares = buildShares({ mode: 'SEAT', lines, grandTotal: grand, extra, paidBySeat: new Map([[2, D(100)]]) });
    expect(shares.map((s) => s.label)).toEqual(['Seat 1', 'Seat 2']);
    expect(sum(shares).toFixed(2)).toBe(grand.toFixed(2));
    expect(shares[1].paid.toFixed(2)).toBe('100.00');
    expect(shares[1].due.equals(shares[1].amount.sub(100))).toBe(true);
  });

  it('by item: a shared item is split equally across the seats it is assigned to', () => {
    const shares = buildShares({ mode: 'ITEMS', assign: 'b:1,b:2', lines, grandTotal: grand, extra, paidBySeat: new Map() });
    const seat1 = shares.find((s) => s.seat === 1)!;
    expect(seat1.itemIds).toEqual(['a', 'b']);
    expect(sum(shares).toFixed(2)).toBe(grand.toFixed(2));
  });

  it('rejects a bad assignment', () => {
    expect(() => buildShares({ mode: 'ITEMS', assign: 'zzz:1', lines, grandTotal: grand, extra, paidBySeat: new Map() })).toThrow();
  });
});
