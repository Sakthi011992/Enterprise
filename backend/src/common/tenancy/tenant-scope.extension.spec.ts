import { TenantContext } from './tenant-context';
import { scopeOperation } from './tenant-scope.extension';

describe('scopeOperation (tenant scope)', () => {
  it('adds tenantId to where on findMany and keeps the caller filters', async () => {
    const query = jest.fn((args: unknown) => args);

    await TenantContext.run({ tenantId: 't1' }, async () =>
      scopeOperation('Product', 'findMany', { where: { deletedAt: null } }, query),
    );

    expect(query).toHaveBeenCalledWith({ where: { deletedAt: null, tenantId: 't1' } });
  });

  it('adds tenantId to where for count when called without args', async () => {
    const query = jest.fn((args: unknown) => args);

    await TenantContext.run({ tenantId: 't1' }, async () => scopeOperation('Order', 'count', undefined, query));

    expect(query).toHaveBeenCalledWith({ where: { tenantId: 't1' } });
  });

  it('sets tenantId on create when it is missing', async () => {
    const query = jest.fn((args: unknown) => args);

    await TenantContext.run({ tenantId: 't1' }, async () =>
      scopeOperation('Product', 'create', { data: { name: 'Coffee' } }, query),
    );

    expect(query).toHaveBeenCalledWith({ data: { name: 'Coffee', tenantId: 't1' } });
  });

  it('sets tenantId on every row of createMany', async () => {
    const query = jest.fn((args: unknown) => args);

    await TenantContext.run({ tenantId: 't1' }, async () =>
      scopeOperation('Product', 'createMany', { data: [{ name: 'A' }, { name: 'B' }] }, query),
    );

    expect(query).toHaveBeenCalledWith({
      data: [
        { name: 'A', tenantId: 't1' },
        { name: 'B', tenantId: 't1' },
      ],
    });
  });

  it('refuses a create that names another tenant', async () => {
    const query = jest.fn((args: unknown) => args);

    await expect(
      TenantContext.run({ tenantId: 't1' }, async () =>
        scopeOperation('Product', 'create', { data: { name: 'X', tenantId: 't2' } }, query),
      ),
    ).rejects.toThrow('Cross-tenant write refused');
    expect(query).not.toHaveBeenCalled();
  });

  it('adds tenantId to a findUnique where and to upsert where and create', async () => {
    const query = jest.fn((args: unknown) => args);

    await TenantContext.run({ tenantId: 't1' }, async () => {
      scopeOperation('User', 'findUnique', { where: { id: 'u1' } }, query);
      scopeOperation('User', 'upsert', { where: { username: 'a' }, create: { username: 'a' }, update: {} }, query);
    });

    expect(query).toHaveBeenNthCalledWith(1, { where: { id: 'u1', tenantId: 't1' } });
    expect(query).toHaveBeenNthCalledWith(2, {
      where: { username: 'a', tenantId: 't1' },
      create: { username: 'a', tenantId: 't1' },
      update: {},
    });
  });

  it('refuses to move an updated row to another tenant', async () => {
    const query = jest.fn((args: unknown) => args);

    await expect(
      TenantContext.run({ tenantId: 't1' }, async () =>
        scopeOperation('Order', 'update', { where: { id: 'o1' }, data: { tenantId: 't2' } }, query),
      ),
    ).rejects.toThrow('Cross-tenant update refused');
    expect(query).not.toHaveBeenCalled();
  });

  it('passes args through unchanged when the context has no tenant', async () => {
    const query = jest.fn((args: unknown) => args);
    const args = { where: { deletedAt: null } };

    await TenantContext.run({}, async () => scopeOperation('Product', 'findMany', args, query));

    expect(query).toHaveBeenCalledWith({ where: { deletedAt: null } });
  });

  it('passes through for models that are not tenant-scoped', async () => {
    const query = jest.fn((args: unknown) => args);

    await TenantContext.run({ tenantId: 't1' }, async () =>
      scopeOperation('Role', 'findMany', { where: { name: 'ADMIN' } }, query),
    );

    expect(query).toHaveBeenCalledWith({ where: { name: 'ADMIN' } });
  });

  it('bypasses tenant filters inside runAsSystem', async () => {
    const query = jest.fn((args: unknown) => args);

    await TenantContext.run({ tenantId: 't1' }, async () =>
      TenantContext.runAsSystem(async () => scopeOperation('User', 'findFirst', { where: { username: 'x' } }, query)),
    );

    expect(query).toHaveBeenCalledWith({ where: { username: 'x' } });
  });
});
