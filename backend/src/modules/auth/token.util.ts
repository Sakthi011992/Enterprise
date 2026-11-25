import { createHash } from 'crypto';

/** sha256 hex digest, used for reset tokens and device keys. Raw values are never stored. */
export function hashToken(raw: string): string {
  return createHash('sha256').update(raw).digest('hex');
}
