/** Pure KDS rules (PLAN 1.7 KDS). No Nest or Prisma imports, so they are unit-tested directly. */

export const OVERDUE_MS = 5 * 60_000;
export const RECALL_WINDOW_MS = 30 * 60_000;
export const DONE_WINDOW_MS = 2 * 60 * 60_000;

export type KdsColour = 'green' | 'amber' | 'red';
export type KdsAction = 'start' | 'bump' | 'recall' | 'served';

/** green under 5 min, amber 5 to 10 min, red over 10 min (PLAN 1.7). */
export function ticketColour(createdAt: Date, end: Date): KdsColour {
  const minutes = (end.getTime() - createdAt.getTime()) / 60_000;
  if (minutes < 5) return 'green';
  if (minutes <= 10) return 'amber';
  return 'red';
}

export function ageSeconds(from: Date, to: Date): number {
  return Math.max(0, Math.floor((to.getTime() - from.getTime()) / 1000));
}

/**
 * Checks an action against the ticket's current state. Returns the 409 code, or null when the action is
 * allowed. RECALL_TOO_LATE applies to a SERVED ticket past the 30-minute recall window.
 */
export function transitionError(
  action: KdsAction,
  status: string,
  servedAt: Date | null,
  now: Date,
): 'KDS_BAD_STATE' | 'RECALL_TOO_LATE' | null {
  switch (action) {
    case 'start':
      return status === 'NEW' ? null : 'KDS_BAD_STATE';
    case 'bump':
      return status === 'NEW' || status === 'PREPARING' ? null : 'KDS_BAD_STATE';
    case 'served':
      return status === 'READY' ? null : 'KDS_BAD_STATE';
    case 'recall': {
      if (status === 'READY') return null;
      if (status !== 'SERVED') return 'KDS_BAD_STATE';
      if (!servedAt || now.getTime() - servedAt.getTime() > RECALL_WINDOW_MS) return 'RECALL_TOO_LATE';
      return null;
    }
  }
}

/** Mean seconds from ticket creation to ready, over tickets that have been bumped. 0 when there are none. */
export function avgTicketSeconds(rows: { createdAt: Date; readyAt: Date | null }[]): number {
  const spans = rows.filter((r) => r.readyAt).map((r) => (r.readyAt!.getTime() - r.createdAt.getTime()) / 1000);
  if (spans.length === 0) return 0;
  return Math.round(spans.reduce((a, b) => a + b, 0) / spans.length);
}

export interface AllDayLine {
  name: string;
  variantName: string | null;
  quantity: number;
}

/**
 * Items still to make across the day: voided lines and served tickets are left out. Counts add up by
 * product and variant, sorted by name.
 */
export function allDayCounts(
  tickets: { kdsStatus: string; items: { name: string; variantName: string | null; quantity: number; voided: boolean }[] }[],
): AllDayLine[] {
  const totals = new Map<string, AllDayLine>();
  for (const t of tickets) {
    if (t.kdsStatus === 'SERVED') continue;
    for (const i of t.items) {
      if (i.voided) continue;
      const key = `${i.name}|${i.variantName ?? ''}`;
      const line = totals.get(key) ?? { name: i.name, variantName: i.variantName, quantity: 0 };
      line.quantity += i.quantity;
      totals.set(key, line);
    }
  }
  return [...totals.values()].sort((a, b) => a.name.localeCompare(b.name) || (a.variantName ?? '').localeCompare(b.variantName ?? ''));
}

/** Station label for display: BAR becomes "Bar", KITCHEN becomes "Kitchen". */
export function stationLabel(station: string): string {
  return station.charAt(0) + station.slice(1).toLowerCase();
}
