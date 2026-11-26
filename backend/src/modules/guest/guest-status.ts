/** Guest-facing line state (PLAN 2.5), derived from line, ticket and round status. No new columns. */
export type GuestLineState = 'WAITING_WAITER' | 'SENT' | 'COOKING' | 'READY' | 'SERVED' | 'CANCELLED';

export function lineState(lineStatus: string, ticketStatus: string | null | undefined): GuestLineState {
  if (lineStatus === 'VOIDED') return 'CANCELLED';
  if (lineStatus === 'SERVED' || ticketStatus === 'SERVED') return 'SERVED';
  if (ticketStatus === 'READY') return 'READY';
  if (ticketStatus === 'PREPARING') return 'COOKING';
  if (lineStatus === 'SENT' || ticketStatus === 'NEW') return 'SENT';
  // NEW line not yet sent (staff still has to send it).
  return 'WAITING_WAITER';
}

/** State of a line that is still only on the round (no order line yet). */
export function roundOnlyState(roundStatus: string): GuestLineState {
  return roundStatus === 'PENDING' ? 'WAITING_WAITER' : 'CANCELLED';
}

/** GuestOrderView.status from the order status. */
export function guestOrderStatus(orderStatus: string): 'OPEN' | 'BILLED' | 'PAID' | 'CLOSED' {
  switch (orderStatus) {
    case 'BILLED':
      return 'BILLED';
    case 'PAID':
    case 'PARTIALLY_PAID':
      return orderStatus === 'PAID' ? 'PAID' : 'BILLED';
    case 'CLOSED':
    case 'VOID':
    case 'REFUNDED':
      return 'CLOSED';
    default:
      return 'OPEN';
  }
}

/** Ticket for each order line (through Ticket.items[].orderItemId). A later ticket wins. */
export function ticketStatusByLine(
  tickets: { items: unknown; kdsStatus: string; createdAt: Date; startedAt?: Date | null; readyAt?: Date | null; servedAt?: Date | null }[],
): Map<string, { status: string; at: Date }> {
  const out = new Map<string, { status: string; at: Date }>();
  for (const t of tickets) {
    const at = t.servedAt ?? t.readyAt ?? t.startedAt ?? t.createdAt;
    const items = Array.isArray(t.items) ? (t.items as { orderItemId?: string }[]) : [];
    for (const i of items) if (i.orderItemId) out.set(i.orderItemId, { status: t.kdsStatus, at });
  }
  return out;
}
