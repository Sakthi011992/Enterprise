import { HttpException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { GuestConfigService } from './guest-config.service';
import { DEFAULT_GUEST_CONFIG } from './guest-config.types';

const auth = { tenantId: 't1', userId: 'admin' };
const codeOf = async (p: Promise<unknown>) => {
  try {
    await p;
  } catch (e) {
    return { status: (e as HttpException).getStatus(), code: ((e as HttpException).getResponse() as any).code };
  }
  throw new Error('expected failure');
};

async function setup() {
  const hash = await bcrypt.hash('246810', 4);
  let row: any = {
    tenantId: 't1',
    config: { ...DEFAULT_GUEST_CONFIG, verification: { ...DEFAULT_GUEST_CONFIG.verification, staticOtpHash: hash } },
    updatedAt: new Date(),
    updatedById: null,
  };
  const repo: any = {
    find: jest.fn(async () => row),
    upsert: jest.fn(async (_t: string, config: any, updatedById: string) => {
      row = { tenantId: 't1', config, updatedAt: new Date(), updatedById };
      return row;
    }),
  };
  return { svc: new GuestConfigService(repo), repo, hash, row: () => row };
}

describe('GuestConfigService', () => {
  it('GET never returns the OTP or its hash', async () => {
    const { svc, hash } = await setup();
    const v = await svc.view(auth);
    expect(v.verification).toEqual({ method: 'STATIC_OTP', codeLength: 6, hasStaticOtp: true });
    expect(v.minAge).toBe(25);
    const json = JSON.stringify(v);
    expect(json).not.toContain(hash);
    expect(json).not.toContain('246810');
    expect(json).not.toContain('staticOtp');
  });

  it('get(tenantId) returns the full config with the hash for internal use', async () => {
    const { svc, hash } = await setup();
    expect((await svc.get('t1')).verification.staticOtpHash).toBe(hash);
  });

  it('defaults apply when no row exists', async () => {
    const svc = new GuestConfigService({ find: jest.fn(async () => null) } as any);
    const v = await svc.view(auth);
    expect(v).toMatchObject({ routing: 'WAITER', checkout: 'WAITER', verification: { hasStaticOtp: false } });
  });

  it('PUT saves routing and a new static OTP (re-hashed) and does not echo it', async () => {
    const { svc, row } = await setup();
    const v = await svc.update({ routing: 'DIRECT', verification: { newStaticOtp: '135790' } }, auth);
    expect(v.routing).toBe('DIRECT');
    expect(JSON.stringify(v)).not.toContain('135790');
    const stored = row().config.verification.staticOtpHash;
    expect(await bcrypt.compare('135790', stored)).toBe(true);
    expect(row().updatedById).toBe('admin');
  });

  it('PUT switches to TABLE_PIN and keeps other fields', async () => {
    const { svc } = await setup();
    const v = await svc.update({ verification: { method: 'TABLE_PIN' }, minAge: 21 }, auth);
    expect(v).toMatchObject({ minAge: 21, routing: 'WAITER', verification: { method: 'TABLE_PIN', hasStaticOtp: true } });
  });

  it('rejects SMS_OTP and non-WAITER checkout as NOT_AVAILABLE', async () => {
    const { svc, repo } = await setup();
    expect(await codeOf(svc.update({ verification: { method: 'SMS_OTP' } }, auth))).toEqual({ status: 400, code: 'NOT_AVAILABLE' });
    expect(await codeOf(svc.update({ checkout: 'ONLINE' }, auth))).toEqual({ status: 400, code: 'NOT_AVAILABLE' });
    expect(await codeOf(svc.update({ checkout: 'BOTH' }, auth))).toEqual({ status: 400, code: 'NOT_AVAILABLE' });
    expect(repo.upsert).not.toHaveBeenCalled();
  });

  it('validates the new OTP against codeLength', async () => {
    const { svc } = await setup();
    expect((await codeOf(svc.update({ verification: { newStaticOtp: '12a456' } }, auth))).code).toBe('STATIC_OTP_INVALID');
    expect((await codeOf(svc.update({ verification: { newStaticOtp: '1234' } }, auth))).code).toBe('STATIC_OTP_INVALID');
    expect((await codeOf(svc.update({ verification: { codeLength: 4 } }, auth))).code).toBe('STATIC_OTP_REQUIRED');
    const v = await svc.update({ verification: { codeLength: 4, newStaticOtp: '2468' } }, auth);
    expect(v.verification.codeLength).toBe(4);
  });

  it('STATIC_OTP needs a code to be set', async () => {
    const svc = new GuestConfigService({ find: jest.fn(async () => null), upsert: jest.fn() } as any);
    expect((await codeOf(svc.update({ routing: 'DIRECT' }, auth))).code).toBe('STATIC_OTP_REQUIRED');
  });
});
