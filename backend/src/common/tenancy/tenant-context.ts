import { AsyncLocalStorage } from 'async_hooks';

export interface TenantStore {
  tenantId?: string;
  outletId?: string;
  userId?: string;
  /** When true, tenant filters are skipped (seed, cross-tenant system lookups). */
  system?: boolean;
}

const storage = new AsyncLocalStorage<TenantStore>();

/**
 * Request-scoped tenant context. The middleware opens a store per request; the JWT strategy
 * fills in tenantId/outletId/userId. PrismaService reads it on every query.
 */
export class TenantContext {
  static get(): TenantStore | undefined {
    return storage.getStore();
  }

  /** Merges values into the current store. Outside any store it starts one for this async flow. */
  static set(partial: TenantStore): void {
    const store = storage.getStore();
    if (store) {
      Object.assign(store, partial);
    } else {
      storage.enterWith({ ...partial });
    }
  }

  /** Runs `fn` with a fresh store (copied from `store`). */
  static run<R>(store: TenantStore, fn: () => R): R {
    return storage.run({ ...store }, fn);
  }

  /** Runs `fn` with tenant filtering bypassed. Keeps any tenant fields for lookups that need them. */
  static runAsSystem<R>(fn: () => R): R {
    return storage.run({ ...(storage.getStore() ?? {}), system: true }, fn);
  }
}
