import { Prisma } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { PermissionKey } from '../../common/permissions/catalog';

export type ApprovalKind = 'DISCOUNT' | 'VOID' | 'REFUND' | 'NO_SALE' | 'TAB_NO_SECURITY';

/** Permission that decides who may approve each kind (Approval rows and the notification's permissionKey). */
export const APPROVAL_PERMISSION: Record<ApprovalKind, PermissionKey> = {
  DISCOUNT: 'sales.discount.give',
  VOID: 'sales.void',
  REFUND: 'sales.void',
  NO_SALE: 'sales.payments.take',
  TAB_NO_SECURITY: 'sales.tab.open',
};

/** An approval is usable this long after the manager decided it. */
export const APPROVAL_TTL_MS = 15 * 60_000;

function fail(message: string): never {
  throw apiError(400, 'INVALID_PAYLOAD', message);
}

/** Checks the payload shape for each kind (see PLAN.md 1.2 Approval.payload). */
export function validateApprovalPayload(type: ApprovalKind, payload: Record<string, unknown>): void {
  if (!payload || typeof payload !== 'object') fail('payload is required');
  switch (type) {
    case 'DISCOUNT': {
      if (payload.type !== 'PERCENT' && payload.type !== 'FLAT') fail('discount payload needs type PERCENT or FLAT');
      if (typeof payload.value !== 'number' || !(payload.value > 0)) fail('discount payload needs a positive value');
      if (payload.itemIds !== undefined && !isStringArray(payload.itemIds)) fail('itemIds must be a list of ids');
      return;
    }
    case 'VOID': {
      const ok = payload.itemIds === 'order' || (isStringArray(payload.itemIds) && payload.itemIds.length > 0);
      if (!ok) fail('void payload needs itemIds (a list) or "order"');
      return;
    }
    case 'REFUND': {
      if (typeof payload.amount !== 'number' || !(payload.amount > 0)) fail('refund payload needs a positive amount');
      return;
    }
    case 'NO_SALE':
      return;
    case 'TAB_NO_SECURITY': {
      if (typeof payload.guestName !== 'string' || payload.guestName.trim().length === 0) fail('tab payload needs a guestName');
      if (typeof payload.tabLimit !== 'number' || !(payload.tabLimit > 0)) fail('tab payload needs a positive tabLimit');
      return;
    }
  }
}

/**
 * Canonical form of the parts of a payload that must match what was approved. The request must
 * produce the same string as the approval it cites, so an approval cannot be reused for another
 * discount, void or refund.
 */
export function canonicalPayload(type: ApprovalKind, payload: Record<string, unknown> | Prisma.JsonValue): string {
  const p = payload as Record<string, unknown>;
  switch (type) {
    case 'DISCOUNT':
      return [p.type, new Prisma.Decimal(p.value as number).toFixed(2), sortedIds(p.itemIds)].join('|');
    case 'VOID':
      return p.itemIds === 'order' ? 'order' : `items:${sortedIds(p.itemIds)}`;
    case 'REFUND':
      return [p.paymentId ?? '', new Prisma.Decimal(p.amount as number).toFixed(2)].join('|');
    case 'NO_SALE':
      return '';
    case 'TAB_NO_SECURITY':
      return [String(p.guestName).trim(), new Prisma.Decimal(p.tabLimit as number).toFixed(2)].join('|');
  }
}

function sortedIds(v: unknown): string {
  return Array.isArray(v) ? [...(v as string[])].sort().join(',') : '';
}

function isStringArray(v: unknown): v is string[] {
  return Array.isArray(v) && v.every((x) => typeof x === 'string');
}
