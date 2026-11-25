import { BarTab, BottleLockerEntry, BottleLockerEvent, Order, Prisma } from '@prisma/client';
import { money } from '../orders/order-pricing';
import { isNearLimit, percentUsed } from './tab-math';

const D = (v: Prisma.Decimal | string | number) => new Prisma.Decimal(v);

/** Everything a TabView needs, loaded by TabsRepository.loadRows. */
export interface TabRows {
  tab: BarTab;
  order: Order;
  table: { id: string; name: string } | null;
  opener: { id: string; name: string } | null;
  /** Lines on the tab that are not voided. */
  itemCount: number;
}

const iso = (d: Date | null | undefined) => (d ? d.toISOString() : null);

/** TabView (PLAN 1.7): money as 2-dp strings, percent as a 1-dp string. */
export function toTabView(r: TabRows) {
  const { tab, order } = r;
  const limit = D(tab.tabLimit);
  const spent = D(order.grandTotal);
  const remaining = limit.sub(spent);
  return {
    id: tab.id,
    number: tab.number,
    guestName: tab.guestName,
    mobile: tab.mobile,
    ageChecked: tab.ageChecked,
    security: tab.security,
    cardLast4: tab.cardLast4,
    amountHeld: money(tab.amountHeld),
    houseAccount: tab.houseAccount,
    tabLimit: money(limit),
    warnAtPercent: tab.warnAtPercent,
    spent: money(spent),
    remaining: money(remaining.isNegative() ? 0 : remaining),
    percentUsed: percentUsed(spent, limit).toFixed(1),
    nearLimit: isNearLimit(spent, limit, tab.warnAtPercent),
    linkType: tab.linkType,
    linkLabel: tab.linkLabel,
    table: r.table,
    status: tab.status,
    openedAt: tab.openedAt.toISOString(),
    closedAt: iso(tab.closedAt),
    openedBy: { id: tab.openedById, name: r.opener?.name ?? '' },
    orderId: tab.orderId,
    orderStatus: order.status,
    itemCount: r.itemCount,
  };
}

export type TabView = ReturnType<typeof toTabView>;

export interface LockerRow extends BottleLockerEntry {
  events: BottleLockerEvent[];
}

/** LockerView (PLAN 1.7). `expired` compares the expiry date with the outlet's business date. */
export function toLockerView(e: LockerRow, todayIso: string, names: Map<string, string>) {
  const expiresIso = e.expiresAt.toISOString().slice(0, 10);
  return {
    id: e.id,
    guestName: e.guestName,
    mobile: e.mobile,
    cardLast4: e.cardLast4,
    guestLabel: e.cardLast4 ? `${e.guestName} · ••${e.cardLast4}` : e.guestName,
    stockItemId: e.stockItemId,
    bottleName: e.bottleName,
    bottleMl: e.bottleMl,
    remainingMl: e.remainingMl,
    storedAt: e.storedAt.toISOString(),
    expiresAt: expiresIso,
    status: e.status,
    expired: expiresIso < todayIso,
    events: e.events.map((ev) => ({
      kind: ev.kind,
      ml: ev.ml,
      by: names.get(ev.byId) ?? ev.byId,
      note: ev.note,
      createdAt: ev.createdAt.toISOString(),
    })),
  };
}

export type LockerView = ReturnType<typeof toLockerView>;
