/**
 * Port that G-B's guest ordering code calls (PLAN 2.6). G-B declares the same interface and injects it with
 * `@Inject(GUEST_EVENTS)`. RealtimeModule (global) provides and exports
 * `{ provide: GUEST_EVENTS, useExisting: GuestEventsService }`.
 */
export const GUEST_EVENTS = 'GUEST_EVENTS';

/**
 * Optional builder of the guest-safe GuestOrderView (PLAN 2.5), provided by G-B. When it is not bound,
 * `guest.order.updated` carries `{ orderId, changed: true }` and the guest app re-fetches `GET /guest/order`.
 */
export const GUEST_ORDER_VIEW = 'GUEST_ORDER_VIEW';

export interface GuestOrderViewBuilder {
  build(orderId: string): Promise<unknown | null>;
}

/** A guest round line as staff see it. No costs. */
export interface GuestRequestLine {
  name: string;
  variant?: string | null;
  modifiers?: string[];
  qty: number;
  lineTotal?: number | string;
  note?: string | null;
}

export interface GuestRequestEventInput {
  requestId: string;
  tenantId: string;
  outletId: string;
  /** Table label, e.g. "R4". */
  table: string;
  /** Guest name. */
  by: string;
  /** Guest phone; masked before it leaves the server. */
  phone?: string | null;
  lines: GuestRequestLine[];
  total: number | string;
  claimedById?: string | null;
}

export interface GuestRequestDecidedInput {
  requestId: string;
  outletId: string;
  status: 'PENDING' | 'CONFIRMED' | 'REJECTED' | 'CANCELLED' | 'EXPIRED';
  claimedById?: string | null;
}

export interface ServiceRequestEventInput {
  id: string;
  tenantId: string;
  outletId: string;
  /** Table label. */
  table: string;
  type: 'CALL_WAITER' | 'BILL';
  status?: 'OPEN' | 'ACKNOWLEDGED' | 'DONE';
  /** Waiter who acknowledged it; also gets the event in their user room. */
  acknowledgedById?: string | null;
}

export interface GuestEvents {
  orderChanged(orderId: string): Promise<void>;
  requestNew(req: GuestRequestEventInput): Promise<void>;
  requestDecided(req: GuestRequestDecidedInput): Promise<void>;
  serviceRequestNew(req: ServiceRequestEventInput): Promise<void>;
  serviceRequestUpdated(req: ServiceRequestEventInput): Promise<void>;
  sessionClosed(sessionId: string, tableId: string): Promise<void>;
}

/** "+919876543210" -> "+91 98•••••210". A number that is not an Indian mobile is fully masked. */
export function maskPhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  const digits = phone.replace(/\D/g, '');
  const local = digits.length === 12 && digits.startsWith('91') ? digits.slice(2) : digits.length === 10 ? digits : null;
  if (!local) return '•••••';
  return `+91 ${local.slice(0, 2)}•••••${local.slice(7)}`;
}
