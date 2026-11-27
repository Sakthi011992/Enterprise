import { OVERDUE_MS, ageSeconds, stationLabel, ticketColour } from './kds-math';

/** The ticket columns a card needs. Ticket rows from Prisma satisfy this structurally. */
export interface KdsTicketRow {
  id: string;
  kind: string;
  station: string;
  seq: number;
  kdsStatus?: string | null;
  createdAt: Date;
  startedAt?: Date | null;
  readyAt?: Date | null;
  servedAt?: Date | null;
  items: unknown;
}

/** The order facts a card shows. Built from an OrderView after a mutation, or from rows when reading the board. */
export interface KdsOrderContext {
  id: string;
  orderNumber: string | null;
  type: string;
  covers: number;
  tableName: string | null;
  tabNumber: string | null;
  waiterId: string | null;
  waiterName: string | null;
  /** orderItemId to line status (NEW, SENT, SERVED, VOIDED). */
  itemStatus: Map<string, string>;
  /** POS, KIOSK or GUEST_QR (Phase 4: KDS shows "QR · R4 · Deepa"). */
  source?: string;
}

/** The part of an OrderView that the KDS reads. */
export interface KdsOrderSource {
  id: string;
  orderNumber: string | null;
  type: string;
  covers: number;
  table: { name: string } | null;
  tab: { number: string } | null;
  waiter: { id: string; name: string } | null;
  items: { id: string; status: string }[];
  source?: string;
}

export interface TicketItemLine {
  orderItemId: string;
  name: string;
  variantName: string | null;
  quantity: number;
  modifiers: string[];
  note: string | null;
  seat: number | null;
  guestName?: string | null;
}

export function contextFromView(v: KdsOrderSource): KdsOrderContext {
  return {
    id: v.id,
    orderNumber: v.orderNumber,
    type: v.type,
    covers: v.covers,
    tableName: v.table?.name ?? null,
    tabNumber: v.tab?.number ?? null,
    waiterId: v.waiter?.id ?? null,
    waiterName: v.waiter?.name ?? null,
    itemStatus: new Map(v.items.map((i) => [i.id, i.status])),
    source: v.source ?? 'POS',
  };
}

/** Lines stored on a ticket (Ticket.items JSON). Unknown shapes read as empty values. */
export function readTicketItems(json: unknown): TicketItemLine[] {
  if (!Array.isArray(json)) return [];
  return json.map((raw) => {
    const r = (raw ?? {}) as Record<string, unknown>;
    return {
      orderItemId: String(r.orderItemId ?? ''),
      name: String(r.name ?? ''),
      variantName: typeof r.variantName === 'string' ? r.variantName : null,
      quantity: Number(r.quantity ?? 1),
      modifiers: Array.isArray(r.modifiers) ? r.modifiers.map(String) : [],
      note: typeof r.note === 'string' ? r.note : null,
      seat: typeof r.seat === 'number' ? r.seat : null,
      guestName: typeof r.guestName === 'string' ? r.guestName : null,
    };
  });
}

const iso = (d: Date | null | undefined): string | null => (d ? d.toISOString() : null);

/** KdsTicket (PLAN 1.7). `colour` runs from creation to now, or to readyAt once bumped. */
export function toKdsTicket(row: KdsTicketRow, ctx: KdsOrderContext, now: Date) {
  const end = row.readyAt ?? now;
  const lines = readTicketItems(row.items);
  return {
    id: row.id,
    kind: row.kind,
    station: row.station,
    seq: row.seq,
    label: `${row.kind} ${row.seq}`,
    kdsStatus: row.kdsStatus ?? 'NEW',
    order: {
      id: ctx.id,
      orderNumber: ctx.orderNumber,
      type: ctx.type,
      tableName: ctx.tableName,
      tabNumber: ctx.tabNumber,
      waiterName: ctx.waiterName,
      covers: ctx.covers,
      source: ctx.source ?? 'POS',
      guestName: lines.find((l) => l.guestName)?.guestName ?? null,
    },
    items: lines.map((i) => ({
      ...i,
      voided: ctx.itemStatus.get(i.orderItemId) === 'VOIDED',
    })),
    createdAt: row.createdAt.toISOString(),
    startedAt: iso(row.startedAt),
    readyAt: iso(row.readyAt),
    servedAt: iso(row.servedAt),
    ageSeconds: ageSeconds(row.createdAt, now),
    colour: ticketColour(row.createdAt, end),
  };
}

/** Where the food or drink goes: table, else tab, else order number. */
export function locationOf(ctx: KdsOrderContext): string {
  return ctx.tableName ?? ctx.tabNumber ?? ctx.orderNumber ?? '';
}

/** ReadyItem (PLAN 1.7). Voided lines are left out. */
export function toReadyItem(row: KdsTicketRow, ctx: KdsOrderContext, now: Date) {
  const readyAt = row.readyAt ?? now;
  const waitingSeconds = ageSeconds(readyAt, now);
  return {
    ticketId: row.id,
    label: `${row.kind} ${row.seq}`,
    station: row.station,
    tableName: ctx.tableName,
    tabNumber: ctx.tabNumber,
    items: readTicketItems(row.items)
      .filter((i) => ctx.itemStatus.get(i.orderItemId) !== 'VOIDED')
      .map((i) => ({ name: i.name, variantName: i.variantName, quantity: i.quantity, seat: i.seat })),
    readyAt: readyAt.toISOString(),
    waitingSeconds,
    overdue: waitingSeconds * 1000 > OVERDUE_MS,
  };
}

/** Text for the waiter's "Ready at the bar" notification. */
export function readyTitle(row: KdsTicketRow, ctx: KdsOrderContext): string {
  const where = row.station === 'BAR' ? 'the bar' : row.station === 'KITCHEN' ? 'the kitchen' : stationLabel(row.station).toLowerCase();
  const place = locationOf(ctx);
  return place ? `Ready at ${where} · ${place}` : `Ready at ${where}`;
}

/** Notification body: "2 × Lager, 1 × Wings". */
export function itemsSummary(row: KdsTicketRow): string {
  return readTicketItems(row.items)
    .map((i) => `${i.quantity} × ${i.name}`)
    .join(', ');
}

/** Wording of the overdue alert, e.g. "R4 · drinks waiting 6 min". */
export function overdueTitle(row: KdsTicketRow, ctx: KdsOrderContext, now: Date): string {
  const minutes = Math.floor(ageSeconds(row.readyAt ?? row.createdAt, now) / 60);
  const what = row.station === 'BAR' ? 'drinks' : 'food';
  return `${locationOf(ctx) || row.kind + ' ' + row.seq} · ${what} waiting ${minutes} min`;
}
