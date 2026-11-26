import { HttpException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { DEFAULT_GUEST_CONFIG, GuestConfigData } from '../guest-config/guest-config.types';
import { GuestAuthService, MAX_ATTEMPTS } from './guest-auth.service';
import { GuestJwtService } from './guest-jwt.service';
import { GuestRateLimiter } from './guest-rate-limiter';
import { maskPhone, newGuestPin, newQrToken, normalizeIndianMobile } from './guest-utils';
import { SmsOtpProvider, StaticOtpProvider, TablePinProvider } from './verification/providers';

const err = (e: unknown) => {
  const r = (e as HttpException).getResponse() as { code: string; details?: any };
  return { status: (e as HttpException).getStatus(), code: r.code, details: r.details };
};
async function failure(p: Promise<unknown>) {
  try {
    await p;
  } catch (e) {
    return err(e);
  }
  throw new Error('expected a failure');
}

const config = new ConfigService({ GUEST_JWT_SECRET: 'guest-secret', JWT_ACCESS_SECRET: 'staff-secret' });
const jwtService = new JwtService({});
let otpHash: string;

beforeAll(async () => {
  otpHash = await bcrypt.hash('246810', 4);
});

function setup(over: Partial<GuestConfigData> = {}, tableOver: Record<string, any> = {}) {
  const cfg: GuestConfigData = {
    ...DEFAULT_GUEST_CONFIG,
    ...over,
    verification: { ...DEFAULT_GUEST_CONFIG.verification, staticOtpHash: otpHash, ...(over.verification ?? {}) },
  };
  const table = {
    id: 'tb1', tenantId: 't1', outletId: 'o1', name: 'R4', status: 'OCCUPIED', isActive: true, qrEnabled: true,
    qrToken: 'QR', guestPin: '4817', outlet: { id: 'o1', name: 'Pegs & Bottles', isActive: true }, ...tableOver,
  };
  const verifications = new Map<string, any>();
  const sessions: any[] = [];
  const participants: any[] = [];
  let seq = 0;
  const repo: any = {
    findTableByQrToken: jest.fn(async (t: string) => (t === table.qrToken ? table : null)),
    findOpenSession: jest.fn(async (tableId: string) => sessions.find((s) => s.tableId === tableId && s.status === 'OPEN') ?? null),
    webThemeId: jest.fn(async () => 'theme1'),
    hasWordmark: jest.fn(async () => false),
    findActiveLock: jest.fn(async (tableId: string, phone: string, deviceKey: string, now: Date) =>
      [...verifications.values()].find(
        (v) => v.tableId === tableId && v.lockedUntil && v.lockedUntil > now && (v.phone === phone || v.deviceKey === deviceKey),
      ) ?? null),
    createVerification: jest.fn(async (data: any) => {
      const v = { id: `v${++seq}`, attempts: 0, lockedUntil: null, verifiedAt: null, ...data };
      verifications.set(v.id, v);
      return v;
    }),
    findVerification: jest.fn(async (id: string) => (verifications.has(id) ? { ...verifications.get(id) } : null)),
    recordFailedAttempt: jest.fn(async (id: string, attempts: number, lockedUntil: Date | null) => {
      Object.assign(verifications.get(id), { attempts, lockedUntil });
    }),
    completeVerification: jest.fn(async (i: any) => {
      verifications.get(i.verificationId).verifiedAt = i.now;
      let s = sessions.find((x) => x.tableId === i.table.id && x.status === 'OPEN');
      if (!s) {
        s = { id: `s${sessions.length + 1}`, tableId: i.table.id, status: 'OPEN', createdAt: i.now };
        sessions.push(s);
      }
      let p = participants.find((x) => x.sessionId === s.id && x.deviceKey === i.deviceKey);
      if (!p) {
        p = { id: `p${participants.length + 1}`, sessionId: s.id, deviceKey: i.deviceKey };
        participants.push(p);
      }
      Object.assign(p, { name: i.name, phone: i.phone, verifiedAt: i.now, verifyMethod: i.method });
      return { session: s, participant: p };
    }),
  };
  const guestConfig: any = { get: jest.fn(async () => cfg) };
  const jwt = new GuestJwtService(jwtService, config);
  const limiter = new GuestRateLimiter();
  const svc = new GuestAuthService(repo, guestConfig, jwt, limiter, [
    new StaticOtpProvider(),
    new TablePinProvider(),
    new SmsOtpProvider(),
  ]);
  let now = new Date('2026-11-27T19:00:00Z').getTime();
  svc.now = () => new Date(now);
  limiter.now = () => now;
  const advance = (ms: number) => (now += ms);
  return { svc, repo, table, sessions, participants, verifications, jwt, limiter, advance };
}

const body = (o: Record<string, any> = {}) => ({
  deviceKey: 'device-key-0001', name: 'Deepa', phone: '98765 43210', consent: true, ...o,
});

describe('guest utils', () => {
  it('normalises Indian mobiles to E.164', () => {
    expect(normalizeIndianMobile('9876543210')).toBe('+919876543210');
    expect(normalizeIndianMobile('+91 98765-43210')).toBe('+919876543210');
    expect(normalizeIndianMobile('919876543210')).toBe('+919876543210');
    expect(normalizeIndianMobile('09876543210')).toBe('+919876543210');
    expect(normalizeIndianMobile('5876543210')).toBeNull(); // must start 6-9
    expect(normalizeIndianMobile('+1 9876543210')).toBeNull();
    expect(normalizeIndianMobile('98765')).toBeNull();
    expect(normalizeIndianMobile('98765abc10')).toBeNull();
  });
  it('masks phones and makes tokens', () => {
    expect(maskPhone('+919876543210')).toBe('+91 98•••••210');
    expect(newQrToken()).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(newGuestPin()).toMatch(/^\d{4}$/);
  });
});

describe('GuestAuthService.lookup', () => {
  it('returns table, safe settings and seated flag; unknown token is 404', async () => {
    const { svc } = setup();
    const r = await svc.lookup('QR');
    expect(r).toMatchObject({ table: { name: 'R4' }, seated: true, sessionOpen: false, themeId: 'theme1' });
    expect(r.settings.verification).toEqual({ method: 'STATIC_OTP', codeLength: 6 });
    expect(JSON.stringify(r)).not.toContain(otpHash);
    expect(JSON.stringify(r)).not.toContain('4817');
    expect(await failure(svc.lookup('nope'))).toMatchObject({ status: 404, code: 'TABLE_NOT_FOUND' });
  });
});

describe('GuestAuthService.start validation', () => {
  it('accepts valid input and stores the phone as E.164', async () => {
    const { svc, verifications } = setup();
    const r = await svc.start('QR', body(), '1.1.1.1');
    expect(r).toEqual({ verificationId: 'v1', method: 'STATIC_OTP', codeLength: 6 });
    expect(verifications.get('v1')).toMatchObject({ phone: '+919876543210', name: 'Deepa', tableId: 'tb1' });
  });

  it.each([
    [{ name: '' }, 'NAME_INVALID'],
    [{ name: '   ' }, 'NAME_INVALID'],
    [{ name: 'x'.repeat(41) }, 'NAME_INVALID'],
    [{ phone: '12345' }, 'PHONE_INVALID'],
    [{ phone: undefined }, 'PHONE_INVALID'],
    [{ consent: false }, 'CONSENT_REQUIRED'],
    [{ consent: undefined }, 'CONSENT_REQUIRED'],
    [{ deviceKey: 'x' }, 'DEVICE_KEY_INVALID'],
  ])('rejects %j with %s', async (o, code) => {
    const { svc } = setup();
    expect(await failure(svc.start('QR', body(o), '1.1.1.1'))).toMatchObject({ status: 400, code });
  });

  it('accepts a 40-character name', async () => {
    const { svc } = setup();
    await expect(svc.start('QR', body({ name: 'x'.repeat(40) }), '1.1.1.1')).resolves.toBeDefined();
  });

  it('refuses when the table is not seated', async () => {
    const { svc } = setup({}, { status: 'FREE' });
    expect(await failure(svc.start('QR', body(), '1.1.1.1'))).toMatchObject({ status: 409, code: 'TABLE_NOT_SEATED' });
  });

  it('allows an unseated table when requireSeated is off', async () => {
    const { svc } = setup({ requireSeated: false }, { status: 'FREE' });
    await expect(svc.start('QR', body(), '1.1.1.1')).resolves.toBeDefined();
  });

  it('refuses when guest ordering is off', async () => {
    const { svc } = setup({ enabled: false });
    expect(await failure(svc.start('QR', body(), '1.1.1.1'))).toMatchObject({ status: 403, code: 'GUEST_ORDERING_OFF' });
  });
});

describe('static OTP', () => {
  it('right code opens a session, returns a guest token and joins the same session for a second phone', async () => {
    const { svc, jwt, sessions } = setup();
    const a = await svc.start('QR', body(), '1.1.1.1');
    const r = await svc.verify('QR', { verificationId: a.verificationId, code: '246810' });
    expect(r.participant).toMatchObject({ name: 'Deepa', phoneMasked: '+91 98•••••210' });
    expect(jwt.verify(r.guestToken)).toEqual({
      kind: 'guest', sessionId: 's1', participantId: 'p1', tableId: 'tb1', outletId: 'o1', tenantId: 't1',
    });

    const b = await svc.start('QR', body({ deviceKey: 'device-key-0002', name: 'Arun', phone: '9123456780' }), '1.1.1.2');
    const r2 = await svc.verify('QR', { verificationId: b.verificationId, code: '246810' });
    expect(r2.session.id).toBe('s1');
    expect(r2.participant.id).toBe('p2');
    expect(sessions).toHaveLength(1);
  });

  it('same device rejoins as the same participant', async () => {
    const { svc, participants } = setup();
    const a = await svc.start('QR', body(), '1.1.1.1');
    await svc.verify('QR', { verificationId: a.verificationId, code: '246810' });
    const b = await svc.start('QR', body({ name: 'Deepa K' }), '1.1.1.1');
    const r = await svc.verify('QR', { verificationId: b.verificationId, code: '246810' });
    expect(r.participant.id).toBe('p1');
    expect(participants).toHaveLength(1);
    expect(participants[0].name).toBe('Deepa K');
  });

  it('wrong code returns CODE_INVALID with attemptsLeft', async () => {
    const { svc } = setup();
    const a = await svc.start('QR', body(), '1.1.1.1');
    expect(await failure(svc.verify('QR', { verificationId: a.verificationId, code: '111111' }))).toEqual({
      status: 401, code: 'CODE_INVALID', details: { attemptsLeft: 4 },
    });
    expect((await failure(svc.verify('QR', { verificationId: a.verificationId, code: '111111' }))).details).toEqual({ attemptsLeft: 3 });
  });

  it('five wrong tries lock for 10 minutes, even with the right code or a new start', async () => {
    const { svc, advance } = setup();
    const a = await svc.start('QR', body(), '1.1.1.1');
    for (let i = 1; i < MAX_ATTEMPTS; i++) {
      expect((await failure(svc.verify('QR', { verificationId: a.verificationId, code: '000000' }))).code).toBe('CODE_INVALID');
    }
    expect(await failure(svc.verify('QR', { verificationId: a.verificationId, code: '000000' }))).toEqual({
      status: 429, code: 'CODE_LOCKED', details: { retryAfter: 600 },
    });
    advance(60_000);
    expect(await failure(svc.verify('QR', { verificationId: a.verificationId, code: '246810' }))).toEqual({
      status: 429, code: 'CODE_LOCKED', details: { retryAfter: 540 },
    });
    expect((await failure(svc.start('QR', body(), '1.1.1.1'))).code).toBe('CODE_LOCKED');
    advance(10 * 60_000);
    const b = await svc.start('QR', body(), '1.1.1.1');
    await expect(svc.verify('QR', { verificationId: b.verificationId, code: '246810' })).resolves.toBeDefined();
  });

  it('a code older than 10 minutes is expired', async () => {
    const { svc, advance } = setup();
    const a = await svc.start('QR', body(), '1.1.1.1');
    advance(10 * 60_000 + 1);
    expect(await failure(svc.verify('QR', { verificationId: a.verificationId, code: '246810' }))).toMatchObject({
      status: 410, code: 'CODE_EXPIRED',
    });
  });

  it('a used challenge cannot be replayed', async () => {
    const { svc } = setup();
    const a = await svc.start('QR', body(), '1.1.1.1');
    await svc.verify('QR', { verificationId: a.verificationId, code: '246810' });
    expect((await failure(svc.verify('QR', { verificationId: a.verificationId, code: '246810' }))).code).toBe('CODE_EXPIRED');
  });

  it('a challenge from another table is not found', async () => {
    const { svc, verifications } = setup();
    const a = await svc.start('QR', body(), '1.1.1.1');
    verifications.get(a.verificationId).tableId = 'other';
    expect((await failure(svc.verify('QR', { verificationId: a.verificationId, code: '246810' }))).code).toBe('VERIFICATION_NOT_FOUND');
  });
});

describe('table PIN', () => {
  const pinCfg = { verification: { method: 'TABLE_PIN', staticOtpHash: null, codeLength: 6 } } as Partial<GuestConfigData>;

  it('start reports a 4-digit code; right PIN verifies', async () => {
    const { svc } = setup(pinCfg);
    const a = await svc.start('QR', body(), '1.1.1.1');
    expect(a).toMatchObject({ method: 'TABLE_PIN', codeLength: 4 });
    const r = await svc.verify('QR', { verificationId: a.verificationId, code: '4817' });
    expect(r.session.tableName).toBe('R4');
  });

  it('wrong PIN is CODE_INVALID', async () => {
    const { svc } = setup(pinCfg);
    const a = await svc.start('QR', body(), '1.1.1.1');
    expect(await failure(svc.verify('QR', { verificationId: a.verificationId, code: '1234' }))).toEqual({
      status: 401, code: 'CODE_INVALID', details: { attemptsLeft: 4 },
    });
  });

  it('a table with no PIN accepts nothing', async () => {
    const { svc } = setup(pinCfg, { guestPin: null });
    const a = await svc.start('QR', body(), '1.1.1.1');
    expect((await failure(svc.verify('QR', { verificationId: a.verificationId, code: '' }))).code).toBe('CODE_INVALID');
  });
});

describe('SMS OTP', () => {
  it('start returns 501 NOT_AVAILABLE', async () => {
    const { svc } = setup({ verification: { method: 'SMS_OTP', staticOtpHash: null, codeLength: 6 } });
    expect(await failure(svc.start('QR', body(), '1.1.1.1'))).toMatchObject({ status: 501, code: 'NOT_AVAILABLE' });
  });
});

describe('rate limits', () => {
  it('start: 3 per minute per phone', async () => {
    const { svc, advance } = setup();
    for (let i = 0; i < 3; i++) await svc.start('QR', body(), `10.0.0.${i}`);
    expect(await failure(svc.start('QR', body(), '10.0.0.9'))).toMatchObject({ status: 429, code: 'RATE_LIMITED' });
    // a different phone is not affected
    await expect(svc.start('QR', body({ phone: '9123456780' }), '10.0.0.9')).resolves.toBeDefined();
    advance(60_000);
    await expect(svc.start('QR', body(), '10.0.0.9')).resolves.toBeDefined();
  });

  it('start: 10 per minute per IP', async () => {
    const { svc } = setup();
    for (let i = 0; i < 10; i++) {
      await svc.start('QR', body({ phone: `98765432${String(i).padStart(2, '0')}` }), '2.2.2.2');
    }
    const f = await failure(svc.start('QR', body({ phone: '9000000000' }), '2.2.2.2'));
    expect(f).toMatchObject({ status: 429, code: 'RATE_LIMITED' });
    expect(f.details.retryAfter).toBeGreaterThan(0);
  });

  it('limiter buckets for G-B: 6 rounds per participant, 3 service requests per session', () => {
    const l = new GuestRateLimiter();
    for (let i = 0; i < 6; i++) l.consume('placeOrderPerParticipant', 'p1');
    expect(() => l.consume('placeOrderPerParticipant', 'p1')).toThrow(HttpException);
    for (let i = 0; i < 3; i++) l.consume('serviceRequestPerSession', 's1');
    try {
      l.consume('serviceRequestPerSession', 's1');
      throw new Error('expected');
    } catch (e) {
      expect(err(e)).toMatchObject({ status: 429, code: 'RATE_LIMITED' });
    }
  });
});
