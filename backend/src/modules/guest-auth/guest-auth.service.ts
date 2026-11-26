import { Inject, Injectable } from '@nestjs/common';
import { apiError } from '../../common/filters/api-error';
import { GuestConfigService } from '../guest-config/guest-config.service';
import { effectiveCodeLength, GuestConfigData, GuestVerificationMethod } from '../guest-config/guest-config.types';
import { GuestStartDto, GuestVerifyDto } from './dto/guest-auth.dto';
import { GuestAuthRepository, GuestTable } from './guest-auth.repository';
import { GuestJwtService } from './guest-jwt.service';
import { GuestRateLimiter } from './guest-rate-limiter';
import { maskPhone, normalizeIndianMobile } from './guest-utils';
import { VERIFICATION_PROVIDERS, VerificationProvider } from './verification/verification-provider';

export const CODE_TTL_MS = 10 * 60_000;
export const LOCK_MS = 10 * 60_000;
export const MAX_ATTEMPTS = 5;

/** QR lookup, start and verify (PLAN 2.3). */
@Injectable()
export class GuestAuthService {
  /** Clock; tests replace it. */
  now: () => Date = () => new Date();

  constructor(
    private repo: GuestAuthRepository,
    private config: GuestConfigService,
    private jwt: GuestJwtService,
    private limiter: GuestRateLimiter,
    @Inject(VERIFICATION_PROVIDERS) private providers: VerificationProvider[],
  ) {}

  /** GET /guest/t/:qrToken */
  async lookup(qrToken: string) {
    const table = await this.tableOr404(qrToken);
    const cfg = await this.config.get(table.tenantId);
    const [session, themeId] = await Promise.all([this.repo.findOpenSession(table.id), this.repo.webThemeId()]);
    const logoUrl = themeId && (await this.repo.hasWordmark(themeId))
      ? `branding/${themeId}/logo?role=WORDMARK&variant=LIGHT`
      : null;
    return {
      table: { id: table.id, name: table.name },
      outlet: { id: table.outlet.id, name: table.outlet.name },
      logoUrl,
      themeId,
      settings: {
        enabled: cfg.enabled && table.qrEnabled,
        routing: cfg.routing,
        verification: { method: cfg.verification.method, codeLength: effectiveCodeLength(cfg) },
        ageGate: cfg.ageGate,
        minAge: cfg.minAge,
        requireSeated: cfg.requireSeated,
        checkout: cfg.checkout,
      },
      seated: table.status === 'OCCUPIED',
      sessionOpen: !!session,
    };
  }

  /** POST /guest/t/:qrToken/start */
  async start(qrToken: string, dto: GuestStartDto, ip: string) {
    this.limiter.consume('startPerIp', ip || 'unknown');

    const table = await this.tableOr404(qrToken);
    const cfg = await this.enabledConfig(table);

    const name = typeof dto.name === 'string' ? dto.name.trim().replace(/\s+/g, ' ') : '';
    if (name.length < 1 || name.length > 40) {
      throw apiError(400, 'NAME_INVALID', 'Enter your name (up to 40 characters)');
    }
    const phone = normalizeIndianMobile(dto.phone);
    if (!phone) throw apiError(400, 'PHONE_INVALID', 'Enter a valid 10-digit Indian mobile number');
    const deviceKey = typeof dto.deviceKey === 'string' ? dto.deviceKey.trim() : '';
    if (!/^[A-Za-z0-9_-]{8,128}$/.test(deviceKey)) {
      throw apiError(400, 'DEVICE_KEY_INVALID', 'deviceKey must be 8-128 url-safe characters');
    }
    if (dto.consent !== true) {
      throw apiError(400, 'CONSENT_REQUIRED', 'Please agree to the use of your number for this order');
    }
    this.assertSeated(cfg, table);

    this.limiter.consume('startPerPhone', phone);

    const now = this.now();
    const lock = await this.repo.findActiveLock(table.id, phone, deviceKey, now);
    if (lock?.lockedUntil) throw codeLocked(lock.lockedUntil, now);

    const method = cfg.verification.method;
    const { codeHash } = await this.provider(method).start({ config: cfg, table, phone });

    const v = await this.repo.createVerification({
      tableId: table.id,
      phone,
      name,
      deviceKey,
      consentAt: now,
      method,
      codeHash,
      expiresAt: new Date(now.getTime() + CODE_TTL_MS),
    });
    return { verificationId: v.id, method, codeLength: effectiveCodeLength(cfg) };
  }

  /** POST /guest/t/:qrToken/verify */
  async verify(qrToken: string, dto: GuestVerifyDto) {
    const table = await this.tableOr404(qrToken);
    const cfg = await this.enabledConfig(table);

    const v = dto.verificationId ? await this.repo.findVerification(dto.verificationId) : null;
    if (!v || v.tableId !== table.id) {
      throw apiError(404, 'VERIFICATION_NOT_FOUND', 'Start again by entering your details');
    }
    const now = this.now();
    if (v.lockedUntil && v.lockedUntil > now) throw codeLocked(v.lockedUntil, now);
    if (v.verifiedAt || v.expiresAt <= now) {
      throw apiError(410, 'CODE_EXPIRED', 'That code has expired. Start again to get a new one.');
    }
    this.assertSeated(cfg, table);

    const code = typeof dto.code === 'string' ? dto.code.trim() : '';
    const ok = await this.provider(v.method as GuestVerificationMethod).check(
      { config: cfg, table, phone: v.phone, codeHash: v.codeHash },
      code,
    );
    if (!ok) {
      const attempts = v.attempts + 1;
      if (attempts >= MAX_ATTEMPTS) {
        const lockedUntil = new Date(now.getTime() + LOCK_MS);
        await this.repo.recordFailedAttempt(v.id, attempts, lockedUntil);
        throw codeLocked(lockedUntil, now);
      }
      await this.repo.recordFailedAttempt(v.id, attempts, null);
      throw apiError(401, 'CODE_INVALID', "That code doesn't match", { attemptsLeft: MAX_ATTEMPTS - attempts });
    }

    const { session, participant } = await this.repo.completeVerification({
      verificationId: v.id,
      table,
      name: v.name,
      phone: v.phone,
      deviceKey: v.deviceKey,
      consentAt: v.consentAt,
      method: v.method,
      now,
    });

    const guestToken = this.jwt.sign({
      sessionId: session.id,
      participantId: participant.id,
      tableId: table.id,
      outletId: table.outletId,
      tenantId: table.tenantId,
    });
    return {
      guestToken,
      session: { id: session.id, tableId: table.id, tableName: table.name, status: session.status, createdAt: session.createdAt },
      participant: {
        id: participant.id,
        name: participant.name,
        phoneMasked: maskPhone(participant.phone),
        verifiedAt: participant.verifiedAt,
      },
    };
  }

  private async tableOr404(qrToken: string): Promise<GuestTable> {
    const table = qrToken ? await this.repo.findTableByQrToken(qrToken) : null;
    if (!table || !table.isActive || !table.outlet.isActive) {
      throw apiError(404, 'TABLE_NOT_FOUND', 'This QR code is not valid. Ask staff for help.');
    }
    return table;
  }

  private async enabledConfig(table: GuestTable): Promise<GuestConfigData> {
    const cfg = await this.config.get(table.tenantId);
    if (!cfg.enabled || !table.qrEnabled) {
      throw apiError(403, 'GUEST_ORDERING_OFF', 'Ordering from your phone is not available at this table');
    }
    return cfg;
  }

  private assertSeated(cfg: GuestConfigData, table: GuestTable) {
    if (cfg.requireSeated && table.status !== 'OCCUPIED') {
      throw apiError(409, 'TABLE_NOT_SEATED', 'Ask staff to seat you to start ordering');
    }
  }

  private provider(method: GuestVerificationMethod): VerificationProvider {
    const p = this.providers.find((x) => x.method === method);
    if (!p) throw apiError(501, 'NOT_AVAILABLE', 'This verification method is not available');
    return p;
  }
}

function codeLocked(until: Date, now: Date) {
  const retryAfter = Math.max(1, Math.ceil((until.getTime() - now.getTime()) / 1000));
  return apiError(429, 'CODE_LOCKED', 'Too many wrong tries. Please wait and try again.', { retryAfter });
}
