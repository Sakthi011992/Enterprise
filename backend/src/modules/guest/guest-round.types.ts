import { maskPhone } from '../guest-auth/guest-utils';

/** One submitted line of a round (GuestOrderRequest.items), with a price snapshot taken when placed. */
export interface RoundItem {
  productId: string;
  variantId?: string | null;
  quantity: number;
  modifiers: { groupId: string; optionId: string }[];
  note?: string | null;
  // Snapshot (server-side, not from the client)
  name?: string;
  variantName?: string | null;
  modifierNames?: string[];
  unitPrice?: string;
  lineTotal?: string;
  isAlcohol?: boolean;
}

export function readRoundItems(json: unknown): RoundItem[] {
  return Array.isArray(json) ? (json as RoundItem[]) : [];
}

export function roundTotal(items: RoundItem[]): string {
  const cents = items.reduce((s, i) => s + Math.round(Number(i.lineTotal ?? 0) * 100), 0);
  return (cents / 100).toFixed(2);
}

interface RowSource {
  id: string;
  outletId: string;
  orderId: string;
  status: string;
  items: unknown;
  claimedById: string | null;
  decidedById: string | null;
  decidedAt: Date | null;
  rejectReason: string | null;
  createdAt: Date;
  expiresAt: Date;
  participant: { name: string; phone: string };
  session: { tableId: string };
}

/**
 * Staff row for a guest round (GET /guest-requests, claim result, realtime payloads). Shape agreed with
 * G-E: table{id,name} plus tableName, guestName/by, phoneMasked, lines with prices, total, claimedBy.
 */
export function toRequestRow(
  r: RowSource,
  tableName: string,
  names: Map<string, string>,
  roundNo: number | null = null,
): Record<string, unknown> {
  const items = readRoundItems(r.items);
  return {
    id: r.id,
    requestId: r.id,
    outletId: r.outletId,
    orderId: r.orderId,
    tableId: r.session.tableId,
    tableName,
    table: { id: r.session.tableId, name: tableName },
    guestName: r.participant.name,
    by: r.participant.name,
    phoneMasked: maskPhone(r.participant.phone),
    status: r.status,
    lines: items.map((i) => ({
      productId: i.productId,
      variantId: i.variantId ?? null,
      name: i.name ?? '',
      variantName: i.variantName ?? null,
      modifiers: i.modifiers.map((m, k) => ({ groupId: m.groupId, optionId: m.optionId, name: i.modifierNames?.[k] ?? '' })),
      quantity: i.quantity,
      unitPrice: i.unitPrice ?? '0.00',
      lineTotal: i.lineTotal ?? '0.00',
      note: i.note ?? null,
      isAlcohol: i.isAlcohol ?? false,
    })),
    total: roundTotal(items),
    createdAt: r.createdAt.toISOString(),
    expiresAt: r.expiresAt.toISOString(),
    claimedById: r.claimedById,
    claimedByName: r.claimedById ? names.get(r.claimedById) ?? null : null,
    claimedBy: r.claimedById ? { id: r.claimedById, name: names.get(r.claimedById) ?? null } : null,
    decidedAt: r.decidedAt ? r.decidedAt.toISOString() : null,
    rejectReason: r.rejectReason,
    roundNo,
  };
}

export function toServiceRow(
  s: { id: string; outletId: string; tableId: string; type: 'CALL_WAITER' | 'BILL'; status: 'OPEN' | 'ACKNOWLEDGED' | 'DONE'; createdAt: Date; doneAt: Date | null; acknowledgedById: string | null },
  tableName: string,
) {
  return {
    id: s.id,
    outletId: s.outletId,
    tableId: s.tableId,
    tableName,
    table: { id: s.tableId, name: tableName },
    type: s.type,
    status: s.status,
    acknowledgedById: s.acknowledgedById,
    createdAt: s.createdAt.toISOString(),
    doneAt: s.doneAt ? s.doneAt.toISOString() : null,
  };
}
