import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { UpdateGuestConfigDto } from './dto/guest-config.dto';
import { GuestConfigRepository } from './guest-config.repository';
import { GuestConfigData, GuestConfigView, withDefaults } from './guest-config.types';

const CACHE_MS = 10_000;

/**
 * App-level guest configuration (PLAN 2.1). `get(tenantId)` is the internal accessor other modules
 * use (it includes the OTP hash); `view` / `update` back GET/PUT /settings/guest and never expose it.
 */
@Injectable()
export class GuestConfigService {
  private cache = new Map<string, { at: number; data: GuestConfigData; updatedAt: Date | null; updatedById: string | null }>();

  constructor(private repo: GuestConfigRepository) {}

  /** Full configuration including `verification.staticOtpHash`. Defaults apply when no row exists. */
  async get(tenantId: string): Promise<GuestConfigData> {
    return (await this.load(tenantId)).data;
  }

  async view(auth: Pick<AuthUser, 'tenantId'>): Promise<GuestConfigView> {
    const row = await this.load(auth.tenantId);
    return toView(row.data, row.updatedAt, row.updatedById);
  }

  async update(dto: UpdateGuestConfigDto, auth: Pick<AuthUser, 'tenantId' | 'userId'>): Promise<GuestConfigView> {
    const current = await this.get(auth.tenantId);
    const { verification: v, ...rest } = dto;

    const next: GuestConfigData = {
      ...current,
      ...stripUndefined(rest),
      verification: {
        ...current.verification,
        ...(v?.method !== undefined ? { method: v.method } : {}),
        ...(v?.codeLength !== undefined ? { codeLength: v.codeLength } : {}),
      },
    };

    if (next.verification.method === 'SMS_OTP') {
      throw apiError(400, 'NOT_AVAILABLE', 'SMS OTP is not available yet');
    }
    if (next.checkout !== 'WAITER') {
      throw apiError(400, 'NOT_AVAILABLE', 'Online payment is not available yet; checkout must be WAITER');
    }

    if (v?.newStaticOtp !== undefined) {
      const otp = v.newStaticOtp.trim();
      if (!/^\d+$/.test(otp) || otp.length !== next.verification.codeLength) {
        throw apiError(
          400,
          'STATIC_OTP_INVALID',
          `The static OTP must be exactly ${next.verification.codeLength} digits`,
          { codeLength: next.verification.codeLength },
        );
      }
      next.verification.staticOtpHash = await bcrypt.hash(otp, 10);
    } else if (
      v?.codeLength !== undefined &&
      v.codeLength !== current.verification.codeLength &&
      next.verification.staticOtpHash
    ) {
      // The stored code no longer matches the new length.
      throw apiError(400, 'STATIC_OTP_REQUIRED', 'Set a new static OTP when changing the code length');
    }
    if (next.verification.method === 'STATIC_OTP' && !next.verification.staticOtpHash) {
      throw apiError(400, 'STATIC_OTP_REQUIRED', 'Set a static OTP before choosing Static OTP verification');
    }

    const saved = await this.repo.upsert(auth.tenantId, next as any, auth.userId ?? null);
    this.cache.delete(auth.tenantId);
    return toView(next, saved.updatedAt, saved.updatedById);
  }

  private async load(tenantId: string) {
    const hit = this.cache.get(tenantId);
    if (hit && Date.now() - hit.at < CACHE_MS) return hit;
    const row = await this.repo.find(tenantId);
    const entry = {
      at: Date.now(),
      data: withDefaults(row?.config),
      updatedAt: row?.updatedAt ?? null,
      updatedById: row?.updatedById ?? null,
    };
    this.cache.set(tenantId, entry);
    return entry;
  }
}

/** Removes the OTP hash. Exported for tests. */
export function toView(data: GuestConfigData, updatedAt: Date | null, updatedById: string | null): GuestConfigView {
  const { staticOtpHash, ...verification } = data.verification;
  return {
    ...data,
    verification: { ...verification, hasStaticOtp: !!staticOtpHash },
    updatedAt,
    updatedById,
  };
}

function stripUndefined<T extends object>(o: T): Partial<T> {
  return Object.fromEntries(Object.entries(o).filter(([, val]) => val !== undefined)) as Partial<T>;
}
