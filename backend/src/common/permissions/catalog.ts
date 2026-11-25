// Permission catalog, default personas and their matrix (PLAN.md sections 1.1 and 1.2).
// The Phase 1 migration (20261125100000_phase1_foundation) inserts the same data;
// keep both in sync. prisma/seed.ts upserts from this file.

/** Ordered weakest to strongest. Used for "at least" checks. */
export const ACCESS_LEVELS = ['NONE', 'VIEW', 'REQUEST', 'LIMITED', 'APPROVE', 'EDIT'] as const;

export type AccessLevel = (typeof ACCESS_LEVELS)[number];

/** Returns true when `actual` is at least `required` in the ordering above. */
export function levelAtLeast(actual: AccessLevel, required: AccessLevel): boolean {
  return ACCESS_LEVELS.indexOf(actual) >= ACCESS_LEVELS.indexOf(required);
}

export type LimitUnit = 'percent' | 'inr';

export type PermissionKey =
  | 'sales.orders.take'
  | 'sales.payments.take'
  | 'sales.discount.give'
  | 'sales.void'
  | 'sales.tab.open'
  | 'menu.edit'
  | 'menu.mark86'
  | 'stock.count'
  | 'stock.purchaseOrders'
  | 'guests.queue'
  | 'displays.control'
  | 'reports.view'
  | 'admin.users'
  | 'admin.settings'
  | 'admin.themes';

export interface PermissionDefinition {
  key: PermissionKey;
  group: string;
  label: string;
  limitUnit: LimitUnit | null;
  sortOrder: number;
}

export const PERMISSION_CATALOG: readonly PermissionDefinition[] = [
  { key: 'sales.orders.take', group: 'Sales', label: 'Take orders & send KOT/BOT', limitUnit: null, sortOrder: 1 },
  { key: 'sales.payments.take', group: 'Sales', label: 'Take payment & close bill', limitUnit: null, sortOrder: 2 },
  { key: 'sales.discount.give', group: 'Sales', label: 'Give discount', limitUnit: 'percent', sortOrder: 3 },
  { key: 'sales.void', group: 'Sales', label: 'Void item / bill', limitUnit: null, sortOrder: 4 },
  { key: 'sales.tab.open', group: 'Sales', label: 'Open bar tab', limitUnit: 'inr', sortOrder: 5 },
  { key: 'menu.edit', group: 'Menu & stock', label: 'Edit menu & prices', limitUnit: null, sortOrder: 6 },
  { key: 'menu.mark86', group: 'Menu & stock', label: 'Mark item out of stock (86)', limitUnit: null, sortOrder: 7 },
  { key: 'stock.count', group: 'Menu & stock', label: 'Stock count & wastage', limitUnit: null, sortOrder: 8 },
  { key: 'stock.purchaseOrders', group: 'Menu & stock', label: 'Purchase orders', limitUnit: null, sortOrder: 9 },
  { key: 'guests.queue', group: 'Guests & displays', label: 'Walk-in queue', limitUnit: null, sortOrder: 10 },
  { key: 'displays.control', group: 'Guests & displays', label: 'Display Control Center', limitUnit: null, sortOrder: 11 },
  { key: 'reports.view', group: 'Reports', label: 'Reports & day close', limitUnit: null, sortOrder: 12 },
  { key: 'admin.users', group: 'Admin', label: 'Users, personas & permissions', limitUnit: null, sortOrder: 13 },
  { key: 'admin.settings', group: 'Admin', label: 'Outlets, tax, devices & settings', limitUnit: null, sortOrder: 14 },
  { key: 'admin.themes', group: 'Admin', label: 'Themes & branding', limitUnit: null, sortOrder: 15 },
];

export type LoginMethodName = 'PASSWORD' | 'PIN';

export interface PersonaGrant {
  level: AccessLevel;
  /** Percent or INR, only for keys with a limitUnit. */
  limit?: number;
}

export interface DefaultPersona {
  key: string;
  name: string;
  loginMethod: LoginMethodName;
  homeRoute: string;
  isSystem: boolean;
  /** Keys not listed are NONE. */
  matrix: Partial<Record<PermissionKey, PersonaGrant>>;
}

export const DEFAULT_PERSONAS: readonly DefaultPersona[] = [
  {
    key: 'admin',
    name: 'Admin',
    loginMethod: 'PASSWORD',
    homeRoute: '/dashboard',
    isSystem: true,
    matrix: {
      'sales.orders.take': { level: 'EDIT' },
      'sales.payments.take': { level: 'EDIT' },
      'sales.discount.give': { level: 'EDIT' },
      'sales.void': { level: 'EDIT' },
      'sales.tab.open': { level: 'EDIT' },
      'menu.edit': { level: 'EDIT' },
      'menu.mark86': { level: 'EDIT' },
      'stock.count': { level: 'EDIT' },
      'stock.purchaseOrders': { level: 'EDIT' },
      'guests.queue': { level: 'EDIT' },
      'displays.control': { level: 'EDIT' },
      'reports.view': { level: 'EDIT' },
      'admin.users': { level: 'EDIT' },
      'admin.settings': { level: 'EDIT' },
      'admin.themes': { level: 'EDIT' },
    },
  },
  {
    key: 'manager',
    name: 'Manager',
    loginMethod: 'PASSWORD',
    homeRoute: '/dashboard',
    isSystem: false,
    matrix: {
      'sales.orders.take': { level: 'EDIT' },
      'sales.payments.take': { level: 'EDIT' },
      'sales.discount.give': { level: 'LIMITED', limit: 30 },
      'sales.void': { level: 'APPROVE' },
      'sales.tab.open': { level: 'EDIT' },
      'menu.edit': { level: 'EDIT' },
      'menu.mark86': { level: 'EDIT' },
      'stock.count': { level: 'EDIT' },
      'stock.purchaseOrders': { level: 'APPROVE' },
      'guests.queue': { level: 'EDIT' },
      'displays.control': { level: 'LIMITED' },
      'reports.view': { level: 'EDIT' },
      'admin.settings': { level: 'VIEW' },
      'admin.themes': { level: 'VIEW' },
    },
  },
  {
    key: 'cashier',
    name: 'Cashier',
    loginMethod: 'PIN',
    homeRoute: '/pos',
    isSystem: false,
    matrix: {
      'sales.orders.take': { level: 'EDIT' },
      'sales.payments.take': { level: 'EDIT' },
      'sales.discount.give': { level: 'LIMITED', limit: 10 },
      'sales.void': { level: 'REQUEST' },
      'sales.tab.open': { level: 'LIMITED', limit: 5000 },
      'menu.edit': { level: 'VIEW' },
      'guests.queue': { level: 'EDIT' },
      'reports.view': { level: 'LIMITED' },
    },
  },
  {
    key: 'captain',
    name: 'Captain',
    loginMethod: 'PIN',
    homeRoute: '/pos',
    isSystem: false,
    matrix: {
      'sales.orders.take': { level: 'EDIT' },
      'sales.payments.take': { level: 'VIEW' },
      'sales.discount.give': { level: 'LIMITED', limit: 10 },
      'sales.void': { level: 'REQUEST' },
      'sales.tab.open': { level: 'LIMITED', limit: 5000 },
      'menu.edit': { level: 'VIEW' },
      'menu.mark86': { level: 'EDIT' },
      'guests.queue': { level: 'EDIT' },
    },
  },
  {
    key: 'waiter',
    name: 'Waiter',
    loginMethod: 'PIN',
    homeRoute: '/pos',
    isSystem: false,
    matrix: {
      'sales.orders.take': { level: 'EDIT' },
      'sales.void': { level: 'REQUEST' },
      'menu.edit': { level: 'VIEW' },
      'guests.queue': { level: 'VIEW' },
    },
  },
  {
    key: 'bartender',
    name: 'Bartender',
    loginMethod: 'PIN',
    homeRoute: '/pos',
    isSystem: false,
    matrix: {
      'sales.orders.take': { level: 'EDIT' },
      'sales.payments.take': { level: 'EDIT' },
      'sales.discount.give': { level: 'LIMITED', limit: 5 },
      'sales.void': { level: 'REQUEST' },
      'sales.tab.open': { level: 'LIMITED', limit: 10000 },
      'menu.edit': { level: 'VIEW' },
      'menu.mark86': { level: 'EDIT' },
      'stock.count': { level: 'EDIT' },
      'guests.queue': { level: 'VIEW' },
    },
  },
  {
    key: 'chef',
    name: 'Chef',
    loginMethod: 'PIN',
    homeRoute: '/menu',
    isSystem: false,
    matrix: {
      'menu.edit': { level: 'VIEW' },
      'menu.mark86': { level: 'EDIT' },
      'stock.count': { level: 'EDIT' },
      'stock.purchaseOrders': { level: 'REQUEST' },
    },
  },
  {
    key: 'storekeeper',
    name: 'Storekeeper',
    loginMethod: 'PIN',
    homeRoute: '/menu',
    isSystem: false,
    matrix: {
      'menu.edit': { level: 'VIEW' },
      'menu.mark86': { level: 'EDIT' },
      'stock.count': { level: 'EDIT' },
      'stock.purchaseOrders': { level: 'EDIT' },
      'reports.view': { level: 'LIMITED' },
    },
  },
  {
    // Kiosk display device account (main's KIOSK role). Every permission is NONE.
    key: 'kiosk',
    name: 'Kiosk display',
    loginMethod: 'PASSWORD',
    homeRoute: '/kiosk',
    isSystem: true,
    matrix: {},
  },
];
