import { PrismaClient } from '@prisma/client';
import { tenantScope } from '../common/tenancy/tenant-scope.extension';

/**
 * Tenant-scoped models whose create-style inputs omit `tenantId`: the tenant extension fills it in
 * from TenantContext at runtime. Their create/createMany/upsert are typed loosely so existing call
 * sites keep compiling without passing tenantId themselves.
 */
type TenantScopedDelegate =
  | 'outlet'
  | 'persona'
  | 'user'
  | 'product'
  | 'globalTaxSetting'
  | 'order'
  | 'productImportLog'
  | 'auditLog'
  | 'device'
  | 'notification'
  | 'taxClass'
  | 'category'
  | 'modifierGroup'
  | 'combo'
  | 'priceRule'
  | 'area'
  | 'diningTable'
  | 'ticket'
  | 'printer'
  | 'stationRoute'
  | 'printJob'
  | 'approval'
  | 'dayClose';

type TenantFilledCreate<D> = {
  [K in keyof D]: K extends 'create' | 'createMany' | 'upsert' ? (args: any) => any : D[K];
};

type PrismaClientShape = Omit<PrismaClient, TenantScopedDelegate> & {
  [K in TenantScopedDelegate]: TenantFilledCreate<PrismaClient[K]>;
};

/**
 * Keeps the class name and import path so existing modules compile unchanged. The class is the DI
 * token; the interface merge gives it the PrismaClient API. The runtime object comes from
 * createTenantPrismaClient() through the factory provider in PrismaModule.
 */
export class PrismaService {}
export interface PrismaService extends PrismaClientShape {}

/** New PrismaClient with the tenant scope extension applied. */
export function createTenantPrismaClient(): PrismaService {
  return new PrismaClient().$extends(tenantScope) as unknown as PrismaService;
}
