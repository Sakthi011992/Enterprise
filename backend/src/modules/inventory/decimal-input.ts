import { Prisma } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';

/** Quantities and rates arrive as JSON numbers or numeric strings; they are parsed to Prisma.Decimal at once. */
export type DecimalInput = number | string;

const NUMERIC = /^-?\d+(\.\d+)?$/;

export function invalidField(field: string, message: string): Error {
  return apiError(400, 'VALIDATION_FAILED', `${field} ${message}`, { field });
}

/**
 * Parses a decimal input. `dp` is the most decimal places allowed, `min` the lowest value allowed.
 * Returns null only for an optional, absent input.
 */
export function decimalInput(
  value: unknown,
  field: string,
  opts: { dp: number; min?: number; optional?: boolean },
): Prisma.Decimal | null {
  if (value === undefined || value === null || value === '') {
    if (opts.optional) return null;
    throw invalidField(field, 'is required');
  }
  if (typeof value !== 'number' && typeof value !== 'string') throw invalidField(field, 'must be a number');
  const text = String(value).trim();
  if (!NUMERIC.test(text)) throw invalidField(field, 'must be a number');
  const decimals = text.split('.')[1];
  if (decimals && decimals.length > opts.dp) {
    throw invalidField(field, `may have at most ${opts.dp} decimal places`);
  }
  const parsed = new Prisma.Decimal(text);
  if (opts.min !== undefined && parsed.lt(opts.min)) throw invalidField(field, `must be ${opts.min} or more`);
  return parsed;
}

/** Strict yyyy-mm-dd check for optional date inputs. */
export function dateInput(value: string | undefined | null, field: string): Date | null {
  if (value === undefined || value === null || value === '') return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw invalidField(field, 'must be a date as YYYY-MM-DD');
  const d = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(d.getTime())) throw invalidField(field, 'must be a date as YYYY-MM-DD');
  return d;
}
