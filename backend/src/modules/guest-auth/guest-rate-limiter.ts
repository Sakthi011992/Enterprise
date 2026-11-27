import { Injectable } from '@nestjs/common';
import { apiError } from '../../common/filters/api-error';

/** Limits from PLAN 2.3. `limit` hits per `windowMs`. */
export const GUEST_RATE_LIMITS = {
  startPerIp: { limit: 10, windowMs: 60_000 },
  startPerPhone: { limit: 3, windowMs: 60_000 },
  placeOrderPerParticipant: { limit: 6, windowMs: 60_000 },
  serviceRequestPerSession: { limit: 3, windowMs: 60_000 },
} as const;

export type GuestRateBucket = keyof typeof GUEST_RATE_LIMITS;

/**
 * Small in-memory sliding-window limiter (single API instance). G-B uses `consume` for
 * `placeOrderPerParticipant` and `serviceRequestPerSession`.
 */
@Injectable()
export class GuestRateLimiter {
  private hits = new Map<string, number[]>();
  private calls = 0;

  /** Clock; tests replace it. */
  now: () => number = Date.now;

  /** Records one hit; throws `429 RATE_LIMITED {retryAfter}` (seconds) when over the limit. */
  consume(bucket: GuestRateBucket, key: string): void {
    const { limit, windowMs } = GUEST_RATE_LIMITS[bucket];
    const retryAfter = this.hit(`${bucket}:${key}`, limit, windowMs);
    if (retryAfter !== null) {
      throw apiError(429, 'RATE_LIMITED', 'Too many requests. Please wait a moment and try again.', { retryAfter });
    }
  }

  /** Returns null when allowed, otherwise the seconds until the next hit is allowed. */
  hit(key: string, limit: number, windowMs: number): number | null {
    const t = this.now();
    const list = (this.hits.get(key) ?? []).filter((x) => t - x < windowMs);
    if (list.length >= limit) {
      this.hits.set(key, list);
      return Math.max(1, Math.ceil((list[0] + windowMs - t) / 1000));
    }
    list.push(t);
    this.hits.set(key, list);
    if (++this.calls % 1000 === 0) this.sweep(t);
    return null;
  }

  private sweep(t: number) {
    const maxWindow = Math.max(...Object.values(GUEST_RATE_LIMITS).map((l) => l.windowMs));
    for (const [k, list] of this.hits) {
      if (!list.length || t - list[list.length - 1] >= maxWindow) this.hits.delete(k);
    }
  }
}
