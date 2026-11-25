import { Prisma } from '@prisma/client';
import { TenantContext } from './tenant-context';

/** Models that carry a tenantId column and are filtered by the current tenant. */
export const TENANT_MODELS = [
  'Outlet',
  'Persona',
  'User',
  'Product',
  'GlobalTaxSetting',
  'Order',
  'ProductImportLog',
  'AuditLog',
  'Device',
  'Notification',
  'TaxClass',
  'Category',
  'ModifierGroup',
  'Combo',
  'PriceRule',
  'Area',
  'DiningTable',
  'Ticket',
  'Printer',
  'StationRoute',
  'PrintJob',
  'Approval',
  'DayClose',
  // Phase 3 (stock, procurement, bar tabs). Line, level and event models carry no tenantId.
  'StockItem',
  'StockLocation',
  'StockMovement',
  'Recipe',
  'StockTransfer',
  'StockCount',
  'WastageEntry',
  'Vendor',
  'PurchaseOrder',
  'GoodsReceipt',
  'DebitNote',
  'DocumentCounter',
  'BarTab',
  'BottleLockerEntry',
] as const;

export type TenantModel = (typeof TENANT_MODELS)[number];

export function isTenantModel(model: string): model is TenantModel {
  return (TENANT_MODELS as readonly string[]).includes(model);
}

// Read/bulk operations: tenantId is added to `where`.
const WHERE_OPERATIONS = new Set([
  'findMany',
  'findFirst',
  'findFirstOrThrow',
  'count',
  'aggregate',
  'groupBy',
  'updateMany',
  'deleteMany',
]);

// Single-record operations: tenantId is added to `where` as an extra filter. Prisma 5 supports
// non-unique filters on unique selectors, so a row from another tenant is reported as not found.
const UNIQUE_WHERE_OPERATIONS = new Set(['findUnique', 'findUniqueOrThrow', 'update', 'delete']);

type QueryFn = (args: any) => any;

/**
 * Applies the tenant rule to one Prisma operation. Pure apart from reading TenantContext, so
 * tests can call it with a mocked `query`.
 *
 * - No tenantId in context, system context, or a model outside TENANT_MODELS: passes through.
 * - Reads and bulk ops: `where.tenantId` is set.
 * - Single-record ops: `where.tenantId` is set (see UNIQUE_WHERE_OPERATIONS).
 * - create / createMany / upsert.create: `tenantId` is set when missing. An explicit tenantId for
 *   another tenant throws instead of writing across tenants.
 * - update / updateMany / upsert.update: moving a row to another tenant is refused.
 */
export function scopeOperation(model: string, operation: string, args: any, query: QueryFn): any {
  const store = TenantContext.get();
  const tenantId = store?.tenantId;
  if (!tenantId || store?.system === true || !isTenantModel(model)) {
    return query(args);
  }

  const next: any = { ...(args ?? {}) };

  const withTenantOnCreate = (row: any) => {
    if (row && row.tenantId !== undefined && row.tenantId !== null && row.tenantId !== tenantId) {
      throw new Error(`Cross-tenant write refused for ${model}`);
    }
    return { ...(row ?? {}), tenantId };
  };
  const assertNoTenantMove = (data: any) => {
    if (data && data.tenantId !== undefined && data.tenantId !== tenantId) {
      throw new Error(`Cross-tenant update refused for ${model}`);
    }
  };

  if (WHERE_OPERATIONS.has(operation) || UNIQUE_WHERE_OPERATIONS.has(operation)) {
    next.where = { ...(next.where ?? {}), tenantId };
    if (operation === 'updateMany' || operation === 'update') assertNoTenantMove(next.data);
    return query(next);
  }

  switch (operation) {
    case 'create':
      next.data = withTenantOnCreate(next.data);
      break;
    case 'createMany':
      next.data = Array.isArray(next.data)
        ? next.data.map(withTenantOnCreate)
        : withTenantOnCreate(next.data);
      break;
    case 'upsert':
      next.create = withTenantOnCreate(next.create);
      assertNoTenantMove(next.update);
      next.where = { ...(next.where ?? {}), tenantId };
      break;
    default:
      break;
  }
  return query(next);
}

/** Prisma query extension that applies scopeOperation to every model operation. */
export const tenantScope = Prisma.defineExtension({
  name: 'tenant-scope',
  query: {
    $allModels: {
      $allOperations({ model, operation, args, query }) {
        return scopeOperation(model, operation, args, query);
      },
    },
  },
});
