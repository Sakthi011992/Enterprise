import { HttpException } from '@nestjs/common';
import { normalizeVariantDefaults } from './variant-defaults';

function codeOf(fn: () => unknown): string | undefined {
  try {
    fn();
    return undefined;
  } catch (err) {
    return err instanceof HttpException ? (err.getResponse() as { code?: string }).code : 'UNEXPECTED';
  }
}

describe('normalizeVariantDefaults', () => {
  it('returns an empty list for no variants', () => {
    expect(normalizeVariantDefaults([])).toEqual([]);
  });

  it('makes the first variant the default when none is marked', () => {
    const out = normalizeVariantDefaults([{ name: '30 ml' }, { name: '60 ml' }]);
    expect(out.map((v) => v.isDefault)).toEqual([true, false]);
  });

  it('keeps the single marked default and clears the rest', () => {
    const out = normalizeVariantDefaults([{ name: '30 ml' }, { name: '60 ml', isDefault: true }, { name: 'Bottle' }]);
    expect(out.map((v) => v.isDefault)).toEqual([false, true, false]);
  });

  it('refuses two defaults', () => {
    expect(codeOf(() => normalizeVariantDefaults([{ name: 'a', isDefault: true }, { name: 'b', isDefault: true }]))).toBe(
      'VARIANT_DEFAULT_MULTIPLE',
    );
  });

  it('refuses duplicate names, ignoring case', () => {
    expect(codeOf(() => normalizeVariantDefaults([{ name: '60 ml' }, { name: '60 ML' }]))).toBe('VARIANT_NAME_DUPLICATE');
  });
});
