import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { CAN_KEY } from '../../common/decorators/can.decorator';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { PermissionsService } from '../personas/permissions.service';
import { PurchaseOrdersController } from './purchase-orders.controller';
import { PurchaseOrdersService } from './purchase-orders.service';

const D = (v: number | string) => new Prisma.Decimal(v);

function autoMock(overrides: Record<string, unknown> = {}): any {
  const store: Record<string, unknown> = { ...overrides };
  return new Proxy(store, {
    get(target, prop) {
      if (typeof prop === 'symbol') return undefined;
      if (!(prop in target)) target[prop] = jest.fn();
      return target[prop];
    },
  });
}

const auth = { userId: 'u1', tenantId: 't1', outletId: 'o1', username: 'sk', permissions: {} } as unknown as AuthUser;

async function codeOf(p: Promise<unknown>): Promise<{ code: string; details?: any }> {
  try {
    await p;
  } catch (e) {
    return (e as HttpException).getResponse() as { code: string; details?: any };
  }
  throw new Error('expected an error');
}

function po(status: string, extra: Record<string, unknown> = {}) {
  return {
    id: 'po1', tenantId: 't1', outletId: 'o1', number: 'PO-0318', vendorId: 'v1', locationId: 'loc', status,
    dueDate: null, transportPermitNo: null, total: D(100), note: null, createdById: 'u1', approvedById: null,
    approvedAt: null, sentAt: null, submittedAt: null, createdAt: new Date(), updatedAt: new Date(), ...extra,
  } as any;
}

function service(findPo: unknown = null, lines: any[] = []) {
  const repo = autoMock({
    transaction: jest.fn(async (fn: (tx: unknown) => unknown) => fn({})),
    findPurchaseOrder: jest.fn(async () => findPo),
    poLines: jest.fn(async () => lines),
    findVendorsByIds: jest.fn(async () => [{ id: 'v1', name: 'City Breweries Supply' }]),
    findLocationsByIds: jest.fn(async () => [{ id: 'loc', name: 'Cellar' }]),
    grnsForPurchaseOrder: jest.fn(async () => []),
    findUsers: jest.fn(async () => []),
    findItemsByIds: jest.fn(async () => []),
    findVendor: jest.fn(async () => ({ id: 'v1' })),
  });
  const docs = autoMock({ next: jest.fn(async () => 1) });
  return { svc: new PurchaseOrdersService(repo, docs), repo, docs };
}

describe('PurchaseOrdersService status transitions', () => {
  it('approve needs a pending order', async () => {
    const { svc } = service(po('DRAFT'));
    expect((await codeOf(svc.approve('po1', auth))).code).toBe('PO_NOT_PENDING');
  });

  it('submit only works from draft', async () => {
    const { svc } = service(po('SENT'));
    expect((await codeOf(svc.submit('po1', auth))).code).toBe('PO_NOT_EDITABLE');
  });

  it('send needs an approved order (or a draft or pending one for an approver)', async () => {
    const { svc } = service(po('RECEIVED'));
    expect((await codeOf(svc.send('po1', auth))).code).toBe('PO_NOT_APPROVED');
  });

  it('cancel is refused once goods have been received', async () => {
    const { svc } = service(po('PARTLY_RECEIVED'), [{ id: 'pl1', qty: D(4), receivedQty: D(1) }]);
    expect((await codeOf(svc.cancel('po1', { reason: 'vendor closed' }, auth))).code).toBe('PO_RECEIVED');
  });

  it('editing a pending order returns it to draft', async () => {
    const { svc, repo } = service(po('PENDING_APPROVAL'));
    repo.findItemsByIds.mockResolvedValue([{ id: 'i1', name: 'Soda' }]);
    await svc.update('po1', { vendorId: 'v1', locationId: 'loc', lines: [{ stockItemId: 'i1', qty: 2, rate: 40 }] } as any, auth).catch(() => undefined);
    const data = repo.updatePurchaseOrder.mock.calls[0]?.[2];
    expect(data?.status).toBe('DRAFT');
  });
});

describe('PurchaseOrdersService approval permission', () => {
  it('approve, send and cancel require stock.purchaseOrders APPROVE', () => {
    for (const handler of [PurchaseOrdersController.prototype.approve, PurchaseOrdersController.prototype.send, PurchaseOrdersController.prototype.cancel]) {
      expect(Reflect.getMetadata(CAN_KEY, handler)).toEqual({ key: 'stock.purchaseOrders', min: 'APPROVE' });
    }
  });

  it('a REQUEST holder cannot approve', () => {
    const perms = new PermissionsService({} as any);
    const requester = { permissions: { 'stock.purchaseOrders': { level: 'REQUEST', limit: null } } };
    expect(perms.check(requester as any, 'stock.purchaseOrders', 'APPROVE')).toBe(false);
    expect(perms.check(requester as any, 'stock.purchaseOrders', 'REQUEST')).toBe(true);
  });
});

describe('PurchaseOrdersService reorder request', () => {
  it('refuses lines whose item has no preferred vendor and names them', async () => {
    const { svc, repo } = service();
    repo.findItemsByIds.mockResolvedValue([
      { id: 'a', name: 'Lime', preferredVendorId: null, lastPurchaseRate: null },
      { id: 'b', name: 'Soda', preferredVendorId: 'v1', lastPurchaseRate: D(40) },
    ]);
    const err = await codeOf(
      svc.reorderRequest({ locationId: 'loc', lines: [{ stockItemId: 'a', qty: 1 }, { stockItemId: 'b', qty: 2 }] } as any, auth),
    );
    expect(err.code).toBe('VENDOR_MISSING');
    expect(err.details).toEqual({ stockItemIds: ['a'] });
  });

  it('creates one pending order per preferred vendor', async () => {
    const { svc, repo, docs } = service();
    repo.findItemsByIds.mockResolvedValue([
      { id: 'a', name: 'Soda', preferredVendorId: 'v1', lastPurchaseRate: D(40) },
      { id: 'b', name: 'Lime', preferredVendorId: 'v2', lastPurchaseRate: D(5) },
      { id: 'c', name: 'Tonic', preferredVendorId: 'v1', lastPurchaseRate: D(30) },
    ]);
    repo.findVendorsByIds.mockResolvedValue([]);
    docs.next.mockResolvedValueOnce(318).mockResolvedValueOnce(319);
    repo.createPurchaseOrder.mockImplementation(async (_tx: unknown, data: any) => ({ id: `po-${data.vendorId}`, ...data, createdAt: new Date() }));
    const out = await svc.reorderRequest(
      { locationId: 'loc', lines: [{ stockItemId: 'a', qty: 2 }, { stockItemId: 'b', qty: 1 }, { stockItemId: 'c', qty: 1 }] } as any,
      auth,
    );
    expect(repo.createPurchaseOrder).toHaveBeenCalledTimes(2);
    const first = repo.createPurchaseOrder.mock.calls[0][1];
    expect(first.vendorId).toBe('v1');
    expect(first.status).toBe('PENDING_APPROVAL');
    expect(first.total.toFixed(2)).toBe('110.00');
    expect(out.purchaseOrders).toHaveLength(2);
  });

  it('returns no orders from a request without lines', async () => {
    const { svc } = service();
    expect((await codeOf(svc.reorderRequest({ locationId: 'loc', lines: [] } as any, auth))).code).toBe('EMPTY_PO');
  });
});
