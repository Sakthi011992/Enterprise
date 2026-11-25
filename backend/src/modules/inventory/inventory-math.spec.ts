import { Prisma } from '@prisma/client';
import { countAdjustment, countDifference, statusFromFlags, wastageValue } from './inventory-math';
import { inr, qty3, unitCostDisplay, money2 } from './inventory-views';
import { decimalInput } from './decimal-input';
import { HttpException } from '@nestjs/common';

const D = (v: number | string) => new Prisma.Decimal(v);

describe('countDifference (outlier rule, PLAN.md 1.7)', () => {
  it('is an outlier when the difference is more than 30% of expected', () => {
    // expected 10, counted 6: -40%
    const r = countDifference(D(10), D(6));
    expect(r.outlier).toBe(true);
    expect(r.differencePercent).toBe('-40.0');
  });

  it('is not an outlier at exactly 30%', () => {
    expect(countDifference(D(10), D(7)).outlier).toBe(false);
  });

  it('reports nothing until both expected and counted are known', () => {
    expect(countDifference(null, D(3))).toEqual({ differencePercent: null, outlier: false });
    expect(countDifference(D(3), null)).toEqual({ differencePercent: null, outlier: false });
  });

  it('treats any count against a zero expectation as an outlier', () => {
    expect(countDifference(D(0), D(1))).toEqual({ differencePercent: null, outlier: true });
    expect(countDifference(D(0), D(0)).outlier).toBe(false);
  });
});

describe('countAdjustment', () => {
  it('is counted minus expected at submit', () => {
    expect(countAdjustment(D(12), D(9)).toFixed(3)).toBe('-3.000');
  });
});

describe('wastageValue', () => {
  it('is qty × avgCost rounded to 2 dp', () => {
    expect(wastageValue(D(750), D('4.16')).toFixed(2)).toBe('3120.00');
  });
});

describe('statusFromFlags priority', () => {
  const none = { negative: false, belowPar: false, variance: false, expiring: false };
  it('is OK with no flags', () => {
    expect(statusFromFlags(none)).toBe('OK');
  });
  it('prefers NEGATIVE over BELOW_PAR over VARIANCE over EXPIRES', () => {
    expect(statusFromFlags({ ...none, negative: true, belowPar: true, variance: true, expiring: true })).toBe('NEGATIVE');
    expect(statusFromFlags({ ...none, belowPar: true, variance: true, expiring: true })).toBe('BELOW_PAR');
    expect(statusFromFlags({ ...none, variance: true, expiring: true })).toBe('VARIANCE');
    expect(statusFromFlags({ ...none, expiring: true })).toBe('EXPIRES');
  });
});

describe('display helpers', () => {
  it('groups rupees the Indian way', () => {
    expect(inr(D(3120))).toBe('₹3,120');
    expect(inr(D(1234567))).toBe('₹12,34,567');
    expect(inr(D(-7800))).toBe('−₹7,800');
  });

  it('formats quantities to 3 dp and money to 2 dp as strings', () => {
    expect(qty3(D(6410))).toBe('6410.000');
    expect(money2(D('4700'))).toBe('4700.00');
  });

  it('shows one pack for a bottle stock item', () => {
    const item = { baseUnit: 'ML' as const, packSize: D(750), packName: 'btl' };
    expect(unitCostDisplay(D('4.16'), item)).toBe('₹3,120 / btl');
  });
});

describe('decimalInput', () => {
  it('accepts numbers and numeric strings', () => {
    expect(decimalInput(1.5, 'qty', { dp: 3 })?.toFixed(3)).toBe('1.500');
    expect(decimalInput('2', 'qty', { dp: 3 })?.toFixed(0)).toBe('2');
  });

  it('refuses too many decimal places, negatives below the minimum and non-numbers', () => {
    expect(() => decimalInput('1.2345', 'qty', { dp: 3 })).toThrow(HttpException);
    expect(() => decimalInput(-1, 'qty', { dp: 3, min: 0 })).toThrow(HttpException);
    expect(() => decimalInput('abc', 'qty', { dp: 3 })).toThrow(HttpException);
  });

  it('returns null for an absent optional input and refuses an absent required one', () => {
    expect(decimalInput(undefined, 'qty', { dp: 3, optional: true })).toBeNull();
    expect(() => decimalInput(undefined, 'qty', { dp: 3 })).toThrow(HttpException);
  });
});
