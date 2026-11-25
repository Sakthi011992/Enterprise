import { HttpException, NotFoundException } from '@nestjs/common';
import { PersonasService } from './personas.service';
import { PermissionsService } from './permissions.service';
import { PersonasRepository } from './personas.repository';
import { PERMISSION_CATALOG } from '../../common/permissions/catalog';
import { AuthUser } from '../../common/decorators/current-user.decorator';

const TENANT = 'tenant-1';

function allEdit(): AuthUser['permissions'] {
  return Object.fromEntries(PERMISSION_CATALOG.map((d) => [d.key, { level: 'EDIT' as const, limit: null }]));
}

function authWith(permissions: AuthUser['permissions']): AuthUser {
  return {
    userId: 'admin-1',
    username: 'admin',
    tenantId: TENANT,
    outletId: 'outlet-1',
    personaId: 'persona-admin',
    personaKey: 'admin',
    permissions,
    role: 'ADMIN',
  };
}

function persona(overrides: Partial<{ id: string; isSystem: boolean; users: number }> = {}) {
  return {
    id: overrides.id ?? 'persona-1',
    key: 'shift-lead',
    name: 'Shift lead',
    description: null,
    homeRoute: '/pos',
    loginMethod: 'PASSWORD' as const,
    isSystem: overrides.isSystem ?? false,
    _count: { userOutlets: overrides.users ?? 0 },
  };
}

function setup(found: ReturnType<typeof persona> | null = persona()) {
  const prisma: any = {
    persona: {
      findFirst: jest.fn(async () => found),
      findMany: jest.fn(async () => []),
      create: jest.fn(async ({ data }: any) => ({ ...persona(), key: data.key, name: data.name })),
      update: jest.fn(async () => persona()),
      delete: jest.fn(async () => ({})),
    },
    permission: {
      findMany: jest.fn(async () => PERMISSION_CATALOG.map((d) => ({ key: d.key }))),
    },
    personaPermission: {
      findMany: jest.fn(async () => []),
      deleteMany: jest.fn(async () => ({ count: 0 })),
      createMany: jest.fn(async () => ({ count: 0 })),
    },
    $transaction: jest.fn(async (ops: Promise<unknown>[]) => Promise.all(ops)),
  };
  const repo = new PersonasRepository(prisma as any);
  const permissions = new PermissionsService(repo);
  const service = new PersonasService(repo, permissions);
  return { service, prisma, permissions };
}

async function caught(promise: Promise<unknown>): Promise<HttpException> {
  try {
    await promise;
  } catch (err) {
    return err as HttpException;
  }
  throw new Error('expected the call to reject');
}

describe('PersonasService', () => {
  it('protects system personas from edit and delete', async () => {
    const { service } = setup(persona({ id: 'admin', isSystem: true }));
    const auth = authWith(allEdit());

    const edit = await caught(service.update('admin', { name: 'Boss' }, auth));
    expect(edit.getStatus()).toBe(403);
    expect(edit.getResponse()).toMatchObject({ code: 'PERSONA_SYSTEM' });

    const del = await caught(service.remove('admin', auth));
    expect(del.getResponse()).toMatchObject({ code: 'PERSONA_SYSTEM' });

    const matrix = await caught(service.setPermissions('admin', { items: [] }, auth));
    expect(matrix.getResponse()).toMatchObject({ code: 'PERSONA_SYSTEM' });
  });

  it('refuses to delete a persona that still has users, with the count in details', async () => {
    const { service, prisma } = setup(persona({ users: 2 }));
    const err = await caught(service.remove('persona-1', authWith(allEdit())));
    expect(err.getStatus()).toBe(409);
    expect(err.getResponse()).toMatchObject({ code: 'PERSONA_IN_USE', details: { userCount: 2 } });
    expect(prisma.persona.delete).not.toHaveBeenCalled();
  });

  it('deletes an unused custom persona', async () => {
    const { service, prisma } = setup(persona({ users: 0 }));
    await expect(service.remove('persona-1', authWith(allEdit()))).resolves.toEqual({ success: true });
    expect(prisma.persona.delete).toHaveBeenCalledWith({ where: { id: 'persona-1' } });
  });

  it('rejects a limit on a key that has no limit unit (LIMIT_NOT_SUPPORTED)', async () => {
    const { service, prisma } = setup();
    const err = await caught(
      service.setPermissions('persona-1', { items: [{ key: 'menu.edit', level: 'VIEW', limit: 5 }] }, authWith(allEdit())),
    );
    expect(err.getStatus()).toBe(400);
    expect(err.getResponse()).toMatchObject({ code: 'LIMIT_NOT_SUPPORTED', details: { key: 'menu.edit' } });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('accepts a limit on a limit-capable key and replaces the matrix', async () => {
    const { service, prisma } = setup();
    await service.setPermissions(
      'persona-1',
      { items: [{ key: 'sales.discount.give', level: 'LIMITED', limit: 15 }] },
      authWith(allEdit()),
    );
    expect(prisma.personaPermission.deleteMany).toHaveBeenCalledWith({ where: { personaId: 'persona-1' } });
    expect(prisma.personaPermission.createMany).toHaveBeenCalledWith({
      data: [{ personaId: 'persona-1', permissionKey: 'sales.discount.give', level: 'LIMITED', limitValue: 15 }],
    });
  });

  it('will not grant a level above the caller\'s own', async () => {
    const { service } = setup();
    const own = allEdit();
    own['menu.edit'] = { level: 'VIEW', limit: null };
    const err = await caught(
      service.setPermissions('persona-1', { items: [{ key: 'menu.edit', level: 'EDIT' }] }, authWith(own)),
    );
    expect(err.getResponse()).toMatchObject({ code: 'PERMISSION_DENIED', details: { key: 'menu.edit', yourLevel: 'VIEW' } });
  });

  it('rejects unknown permission keys', async () => {
    const { service } = setup();
    const err = await caught(
      service.setPermissions('persona-1', { items: [{ key: 'made.up', level: 'VIEW' }] }, authWith(allEdit())),
    );
    expect(err.getResponse()).toMatchObject({ code: 'UNKNOWN_PERMISSION' });
  });

  it('returns 404 for a persona in another tenant (lookup is tenant-scoped)', async () => {
    const { service, prisma } = setup(null);
    await expect(service.update('other', { name: 'x' }, authWith(allEdit()))).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.persona.findFirst).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'other', tenantId: TENANT } }));
  });
});

describe('PermissionsService.assertWithinLimit', () => {
  const { permissions } = setup();

  it('passes inside the limit and fails above it with LIMIT_EXCEEDED', async () => {
    const user = { permissions: { 'sales.discount.give': { level: 'LIMITED' as const, limit: 10 } } } as any;
    expect(() => permissions.assertWithinLimit(user, 'sales.discount.give', 10)).not.toThrow();

    const err = await caught(Promise.resolve().then(() => permissions.assertWithinLimit(user, 'sales.discount.give', 11)));
    expect(err.getResponse()).toMatchObject({ code: 'LIMIT_EXCEEDED', details: { limit: 10 } });
  });

  it('lets APPROVE and EDIT through without a limit', () => {
    const user = { permissions: { 'sales.discount.give': { level: 'APPROVE' as const, limit: null } } } as any;
    expect(() => permissions.assertWithinLimit(user, 'sales.discount.give', 9999)).not.toThrow();
  });
});
