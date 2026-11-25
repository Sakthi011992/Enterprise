import { HttpException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { ApprovalsService } from './approvals.service';
import { AuthUser } from '../../common/decorators/current-user.decorator';

const codeOf = (e: unknown) => (e as HttpException).getResponse() as { code: string; details?: Record<string, unknown> };
const auth = { userId: 'cashier', tenantId: 't1', outletId: 'o1', permissions: {} } as unknown as AuthUser;

describe('ApprovalsService.approveWithPin', () => {
  let pinState: { pinHash: string; failedAttempts: number; lockedUntil: Date | null };

  function build() {
    pinState = { pinHash: bcrypt.hashSync('4321', 4), failedAttempts: 0, lockedUntil: null };
    const repo: any = {
      transaction: (fn: (tx: unknown) => unknown) => fn({}),
      findUserOutlet: jest.fn(async () => ({ personaId: 'mgr', user: { tenantId: 't1', deletedAt: null, isActive: true } })),
      createApproval: jest.fn(async (_tx: unknown, data: any) => ({ id: 'a1', createdAt: new Date(), expiresAt: new Date(), decidedAt: new Date(), ...data })),
      createNotification: jest.fn(),
    };
    const authRepo: any = {
      findStaffPin: jest.fn(async () => ({ ...pinState })),
      updateStaffPin: jest.fn(async (_id: string, data: any) => Object.assign(pinState, data)),
    };
    const permissions: any = {
      forPersona: jest.fn(async () => ({ 'sales.discount.give': { level: 'APPROVE', limit: null } })),
      check: jest.fn(),
    };
    const audit: any = { record: jest.fn() };
    return new ApprovalsService(repo, authRepo, permissions, audit);
  }

  const dto = { type: 'DISCOUNT', payload: { type: 'PERCENT', value: 20, itemIds: [] }, reason: 'Birthday', managerUserId: 'mgr', pin: '0000' } as any;

  it('reports PIN_INVALID with attempts left, then PIN_LOCKED on the third wrong PIN', async () => {
    const svc = build();

    const first = await svc.approveWithPin(auth, dto).catch((e) => e);
    expect(codeOf(first)).toMatchObject({ code: 'PIN_INVALID', details: { attemptsLeft: 2 } });

    const second = await svc.approveWithPin(auth, dto).catch((e) => e);
    expect(codeOf(second)).toMatchObject({ code: 'PIN_INVALID', details: { attemptsLeft: 1 } });

    const third = await svc.approveWithPin(auth, dto).catch((e) => e);
    expect(codeOf(third).code).toBe('PIN_LOCKED');
  });

  it('stays locked even with the right PIN until the lock expires', async () => {
    const svc = build();
    pinState.lockedUntil = new Date(Date.now() + 60_000);

    const err = await svc.approveWithPin(auth, { ...dto, pin: '4321' }).catch((e) => e);
    expect(codeOf(err).code).toBe('PIN_LOCKED');
  });

  it('approves in one step with the right PIN for a manager who holds APPROVE', async () => {
    const svc = build();
    const res = await svc.approveWithPin(auth, { ...dto, pin: '4321' });
    expect(res.status).toBe('APPROVED');
    expect(res.approverId).toBe('mgr');
  });

  it('accepts an approval once and refuses it the second time (single use)', async () => {
    const approval = {
      id: 'a9', type: 'DISCOUNT', status: 'APPROVED', orderId: 'o1', approverId: 'mgr',
      decidedAt: new Date(), payload: { type: 'PERCENT', value: 20, itemIds: [], reason: 'Regular guest' },
    };
    let used = false;
    const repo: any = {
      findApproval: jest.fn(async () => approval),
      consume: jest.fn(async () => (used ? 0 : ((used = true), 1))),
    };
    const svc = new ApprovalsService(repo, {} as any, {} as any, {} as any);
    const payload = { type: 'PERCENT', value: 20, itemIds: [], reason: 'Regular guest' };
    await expect(svc.assertApproved('a9', { outletId: 'out1' }, 'DISCOUNT' as any, payload, 'o1')).resolves.toEqual({ approverId: 'mgr' });
    await expect(svc.assertApproved('a9', { outletId: 'out1' }, 'DISCOUNT' as any, payload, 'o1')).rejects.toMatchObject({ status: 403 });
  });
});
