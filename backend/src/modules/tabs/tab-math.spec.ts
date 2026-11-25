import { Prisma } from '@prisma/client';
import { depositSplit, heldFor, isNearLimit, percentUsed, tabNumber, tabSecurityError, wholePercent } from './tab-math';

const D = (v: number | string) => new Prisma.Decimal(v);

describe('tab math', () => {
  it('reports percent used and the near-limit warning', () => {
    expect(percentUsed(4700, 5000).toFixed(1)).toBe('94.0');
    expect(isNearLimit(4700, 5000, 90)).toBe(true);
    expect(isNearLimit(4499, 5000, 90)).toBe(false);
    expect(isNearLimit(4000, 5000, 80)).toBe(true);
    expect(wholePercent(D(4749.99), 5000)).toBe(94);
  });

  it('applies the deposit up to the bill and returns the rest', () => {
    const over = depositSplit(2000, 1450);
    expect(over.applied.toFixed(2)).toBe('1450.00');
    expect(over.toReturn.toFixed(2)).toBe('550.00');

    const under = depositSplit(500, 1450);
    expect(under.applied.toFixed(2)).toBe('500.00');
    expect(under.toReturn.toFixed(2)).toBe('0.00');
  });

  it('numbers tabs with at least two digits', () => {
    expect(tabNumber(7)).toBe('T-07');
    expect(tabNumber(12)).toBe('T-12');
  });

  it('checks security in the plan order', () => {
    expect(tabSecurityError({ ageChecked: false, security: 'NONE' })).toBe('AGE_CHECK_REQUIRED');
    expect(tabSecurityError({ ageChecked: true, security: 'CARD_PREAUTH', cardLast4: '12' })).toBe('CARD_LAST4_REQUIRED');
    expect(tabSecurityError({ ageChecked: true, security: 'CARD_PREAUTH', cardLast4: '4821' })).toBeNull();
    expect(tabSecurityError({ ageChecked: true, security: 'CASH_DEPOSIT', amountHeld: 0 })).toBe('DEPOSIT_REQUIRED');
    expect(tabSecurityError({ ageChecked: true, security: 'HOUSE_ACCOUNT', houseAccount: '  ' })).toBe('HOUSE_ACCOUNT_REQUIRED');
    expect(tabSecurityError({ ageChecked: true, security: 'NONE' })).toBeNull();
  });

  it('holds money only for card pre-auth and cash deposits', () => {
    expect(heldFor('NONE', 5000).toFixed(2)).toBe('0.00');
    expect(heldFor('CARD_PREAUTH', 5000).toFixed(2)).toBe('5000.00');
    expect(heldFor('CASH_DEPOSIT', undefined).toFixed(2)).toBe('0.00');
  });
});
