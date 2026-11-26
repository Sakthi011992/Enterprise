import { randomBytes, randomInt } from 'crypto';

/**
 * Normalises an Indian mobile number to E.164 ("+919876543210"). Accepts 10 digits, an optional
 * +91 / 91 / 0 prefix, and spaces, dashes, dots or brackets. Returns null when it is not a valid
 * Indian mobile number (10 digits starting with 6-9).
 */
export function normalizeIndianMobile(input: unknown): string | null {
  if (typeof input !== 'string') return null;
  const raw = input.trim();
  if (!/^\+?[\d\s\-().]+$/.test(raw)) return null;
  let digits = raw.replace(/\D/g, '');
  const hasPlus = raw.startsWith('+');
  if (hasPlus) {
    if (!digits.startsWith('91') || digits.length !== 12) return null;
    digits = digits.slice(2);
  } else if (digits.length === 12 && digits.startsWith('91')) {
    digits = digits.slice(2);
  } else if (digits.length === 11 && digits.startsWith('0')) {
    digits = digits.slice(1);
  }
  if (!/^[6-9]\d{9}$/.test(digits)) return null;
  return `+91${digits}`;
}

/** "+919876543210" → "+91 98•••••210" (PLAN 2.3: how staff see guest numbers). */
export function maskPhone(e164: string | null | undefined): string {
  if (!e164) return '';
  const m = /^\+91(\d{10})$/.exec(e164);
  if (!m) return e164.length > 4 ? `${'•'.repeat(e164.length - 3)}${e164.slice(-3)}` : '•••';
  const d = m[1];
  return `+91 ${d.slice(0, 2)}•••••${d.slice(7)}`;
}

/** 22-char url-safe random token (128 bits) for DiningTable.qrToken. */
export function newQrToken(): string {
  return randomBytes(16).toString('base64url');
}

/** Random 4-digit table PIN, "0000"–"9999". */
export function newGuestPin(): string {
  return String(randomInt(0, 10_000)).padStart(4, '0');
}
