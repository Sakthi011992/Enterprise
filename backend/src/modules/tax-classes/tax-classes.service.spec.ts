import { HttpException } from '@nestjs/common';
import { assertComponentsSumToRate } from './tax-classes.service';

describe('assertComponentsSumToRate', () => {
  it('accepts components that add up to the rate', () => {
    expect(() =>
      assertComponentsSumToRate(5, [
        { name: 'CGST', rate: 2.5 },
        { name: 'SGST', rate: 2.5 },
      ]),
    ).not.toThrow();
  });

  it('refuses components that do not add up', () => {
    let caught: unknown;
    try {
      assertComponentsSumToRate(5, [
        { name: 'CGST', rate: 2.5 },
        { name: 'SGST', rate: 2 },
      ]);
    } catch (err) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(HttpException);
    expect((caught as HttpException).getResponse()).toMatchObject({ code: 'TAX_COMPONENTS_MISMATCH' });
  });
});
