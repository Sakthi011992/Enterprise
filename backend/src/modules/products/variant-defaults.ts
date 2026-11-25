import { apiError } from '../../common/filters/api-error';

export interface VariantDraft {
  id?: string;
  name: string;
  isDefault?: boolean;
}

/**
 * Enforces "exactly one default variant if any": two or more defaults are refused, none means the
 * first variant becomes the default. Also refuses duplicate names within one product.
 */
export function normalizeVariantDefaults<T extends VariantDraft>(items: T[]): (T & { isDefault: boolean })[] {
  if (items.length === 0) return [];
  const names = new Set<string>();
  for (const item of items) {
    const key = item.name.trim().toLowerCase();
    if (names.has(key)) throw apiError(400, 'VARIANT_NAME_DUPLICATE', `Two variants are named "${item.name}"`);
    names.add(key);
  }
  const defaults = items.filter((item) => item.isDefault).length;
  if (defaults > 1) throw apiError(400, 'VARIANT_DEFAULT_MULTIPLE', 'Only one variant can be the default');
  const defaultIndex = defaults === 1 ? items.findIndex((item) => item.isDefault) : 0;
  return items.map((item, index) => ({ ...item, isDefault: index === defaultIndex }));
}
