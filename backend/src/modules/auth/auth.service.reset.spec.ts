import { HttpException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { AuthRepository } from './auth.repository';
import { hashToken } from './token.util';
import { PermissionsService } from '../personas/permissions.service';
import { PersonasRepository } from '../personas/personas.repository';

const HOUR = 60 * 60_000;

function setup() {
  const prisma: any = {
    passwordResetToken: {
      findUnique: jest.fn(),
      updateMany: jest.fn(async () => ({ count: 1 })),
      create: jest.fn(async () => ({})),
    },
    user: {
      findFirst: jest.fn(),
      update: jest.fn(async () => ({})),
    },
    $transaction: jest.fn(async (ops: Promise<unknown>[]) => Promise.all(ops)),
  };
  const notifier = { notify: jest.fn(async () => undefined) };
  const config = new ConfigService({
    JWT_ACCESS_SECRET: 'access-secret',
    JWT_REFRESH_SECRET: 'refresh-secret',
    APP_BASE_URL: 'http://app.test',
  });
  const permissions = new PermissionsService(new PersonasRepository(prisma as any));
  const service = new AuthService(new AuthRepository(prisma as any), new JwtService({}), config, permissions, notifier);
  return { service, prisma, notifier };
}

async function caught(promise: Promise<unknown>): Promise<HttpException> {
  try {
    await promise;
  } catch (err) {
    return err as HttpException;
  }
  throw new Error('expected the call to reject');
}

describe('AuthService.resetPassword', () => {
  it('rejects an expired token with RESET_TOKEN_INVALID and changes nothing', async () => {
    const { service, prisma } = setup();
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1', userId: 'u1', usedAt: null, expiresAt: new Date(Date.now() - 1_000),
    });

    const err = await caught(service.resetPassword('some-token-value', 'Newpass1'));
    expect(err.getStatus()).toBe(400);
    expect(err.getResponse()).toMatchObject({ code: 'RESET_TOKEN_INVALID' });
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('rejects a token that was already used', async () => {
    const { service, prisma } = setup();
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1', userId: 'u1', usedAt: new Date(), expiresAt: new Date(Date.now() + HOUR),
    });

    const err = await caught(service.resetPassword('some-token-value', 'Newpass1'));
    expect(err.getResponse()).toMatchObject({ code: 'RESET_TOKEN_INVALID' });
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('rejects an unknown token', async () => {
    const { service, prisma } = setup();
    prisma.passwordResetToken.findUnique.mockResolvedValue(null);
    const err = await caught(service.resetPassword('nope', 'Newpass1'));
    expect(err.getResponse()).toMatchObject({ code: 'RESET_TOKEN_INVALID' });
    expect(prisma.passwordResetToken.findUnique).toHaveBeenCalledWith({ where: { tokenHash: hashToken('nope') } });
  });

  it('rejects a second use when another request claimed the token first', async () => {
    const { service, prisma } = setup();
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1', userId: 'u1', usedAt: null, expiresAt: new Date(Date.now() + HOUR),
    });
    prisma.passwordResetToken.updateMany.mockResolvedValueOnce({ count: 0 });

    const err = await caught(service.resetPassword('raced', 'Newpass1'));
    expect(err.getResponse()).toMatchObject({ code: 'RESET_TOKEN_INVALID' });
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('sets the new hash, bumps tokenVersion and marks the token used', async () => {
    const { service, prisma } = setup();
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1', userId: 'u1', usedAt: null, expiresAt: new Date(Date.now() + HOUR),
    });

    await expect(service.resetPassword('good-token', 'Newpass1')).resolves.toEqual({ success: true });

    expect(prisma.passwordResetToken.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 't1', usedAt: null } }),
    );
    const call = prisma.user.update.mock.calls[0][0] as any;
    expect(call.where).toEqual({ id: 'u1' });
    expect(call.data.tokenVersion).toEqual({ increment: 1 });
    expect(bcrypt.compareSync('Newpass1', call.data.passwordHash)).toBe(true);
  });
});

describe('AuthService.forgotPassword', () => {
  it('returns success without creating anything for an unknown account', async () => {
    const { service, prisma, notifier } = setup();
    prisma.user.findFirst.mockResolvedValue(null);

    await expect(service.forgotPassword('ghost')).resolves.toEqual({ success: true });
    expect(prisma.passwordResetToken.create).not.toHaveBeenCalled();
    expect(notifier.notify).not.toHaveBeenCalled();
  });

  it('stores only the hash of a new 30-minute token and sends the raw one in the link', async () => {
    const { service, prisma, notifier } = setup();
    prisma.user.findFirst.mockResolvedValue({ id: 'u1', username: 'priya', email: 'priya@example.com' });

    await expect(service.forgotPassword('priya')).resolves.toEqual({ success: true });

    const created = (prisma.passwordResetToken.create.mock.calls[0][0] as any).data;
    const url: string = (notifier.notify.mock.calls[0] as unknown as [unknown, string])[1];
    const raw = new URL(url).searchParams.get('token') as string;

    expect(url.startsWith('http://app.test/reset-password?token=')).toBe(true);
    expect(created.tokenHash).toBe(hashToken(raw));
    expect(created.tokenHash).not.toBe(raw);
    expect(created.expiresAt.getTime() - Date.now()).toBeGreaterThan(29 * 60_000);
    expect(created.expiresAt.getTime() - Date.now()).toBeLessThanOrEqual(30 * 60_000);
  });
});
