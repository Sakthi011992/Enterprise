import { Prisma } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { round2 } from '../../common/utils/money.util';

export type SplitMode = 'EQUAL' | 'SEAT' | 'ITEMS';

export interface SplitLine {
  id: string;
  seat: number | null;
  /** Line total including tax, after discounts (OrderItem.lineTotal). */
  total: Prisma.Decimal;
}

export interface SplitShare {
  label: string;
  seat: number | null;
  itemIds: string[];
  amount: Prisma.Decimal;
  paid: Prisma.Decimal;
  due: Prisma.Decimal;
}

export interface BuildSharesInput {
  mode: SplitMode;
  parts?: number;
  /** "itemId:seat,itemId:seat". The same item listed for several seats is shared equally. */
  assign?: string;
  lines: SplitLine[];
  grandTotal: Prisma.Decimal;
  /** Service charge plus round-off: spread over the shares in proportion to their line totals. */
  extra: Prisma.Decimal;
  /** Money already paid per seat (or per part for EQUAL), keyed by seat number. */
  paidBySeat: Map<number, Prisma.Decimal>;
}

const D = (v: Prisma.Decimal | number | string) => new Prisma.Decimal(v);

/**
 * Shares of an order for the pay screen. Amounts come from the priced lines plus their share of the
 * service charge and round-off. The last share takes the remainder, so the shares add up to the
 * grand total exactly.
 */
export function buildShares(input: BuildSharesInput): SplitShare[] {
  if (input.mode === 'EQUAL') return equalShares(input);

  // Weight of each seat: the line totals it is charged for.
  const seatItems = new Map<number, { itemIds: string[]; weight: Prisma.Decimal }>();
  const addTo = (seat: number, itemId: string, weight: Prisma.Decimal) => {
    const cur = seatItems.get(seat) ?? { itemIds: [], weight: D(0) };
    if (!cur.itemIds.includes(itemId)) cur.itemIds.push(itemId);
    cur.weight = cur.weight.add(weight);
    seatItems.set(seat, cur);
  };

  const assignments = input.mode === 'ITEMS' ? parseAssign(input.assign, input.lines) : new Map<string, number[]>();
  for (const line of input.lines) {
    let seats: number[];
    if (input.mode === 'SEAT') seats = [line.seat ?? 1];
    else seats = assignments.get(line.id) ?? [line.seat ?? 1];
    const share = line.total.div(seats.length);
    for (const seat of [...new Set(seats)]) addTo(seat, line.id, share);
  }

  const lineSum = input.lines.reduce((s, l) => s.add(l.total), D(0));
  const seats = [...seatItems.keys()].sort((a, b) => a - b);
  const shares: SplitShare[] = seats.map((seat) => {
    const cur = seatItems.get(seat)!;
    const amount = lineSum.isZero() ? D(0) : cur.weight.add(input.extra.mul(cur.weight).div(lineSum));
    return {
      label: `Seat ${seat}`,
      seat,
      itemIds: cur.itemIds,
      amount: round2(amount),
      paid: input.paidBySeat.get(seat) ?? D(0),
      due: D(0),
    };
  });
  if (lineSum.isZero() && shares.length) {
    // Nothing priced: split the grand total evenly.
    const even = round2(D(input.grandTotal).div(shares.length));
    shares.forEach((s) => (s.amount = even));
  }
  return finalise(shares, input.grandTotal);
}

function equalShares(input: BuildSharesInput): SplitShare[] {
  const parts = input.parts ?? 2;
  if (!Number.isInteger(parts) || parts < 2 || parts > 10) {
    throw apiError(400, 'INVALID_SPLIT', 'Split equally into 2 to 10 parts');
  }
  const shares: SplitShare[] = Array.from({ length: parts }, (_, i) => ({
    label: `Part ${i + 1}`,
    seat: null,
    itemIds: [],
    amount: round2(D(input.grandTotal).div(parts)),
    paid: input.paidBySeat.get(i + 1) ?? D(0),
    due: D(0),
  }));
  return finalise(shares, input.grandTotal);
}

/** Sets `due` and puts the rounding remainder on the last share. */
function finalise(shares: SplitShare[], grandTotal: Prisma.Decimal): SplitShare[] {
  if (shares.length === 0) return shares;
  const others = shares.slice(0, -1).reduce((s, x) => s.add(x.amount), D(0));
  shares[shares.length - 1].amount = round2(D(grandTotal).sub(others));
  for (const s of shares) {
    const due = s.amount.sub(s.paid);
    s.due = due.isNegative() ? D(0) : due;
  }
  return shares;
}

/** Parses assign="itemId:seat,itemId:seat". Items not listed keep their own seat. */
export function parseAssign(assign: string | undefined, lines: SplitLine[]): Map<string, number[]> {
  const out = new Map<string, number[]>();
  if (!assign) return out;
  const known = new Set(lines.map((l) => l.id));
  for (const raw of assign.split(',').map((x) => x.trim()).filter(Boolean)) {
    const [itemId, seatText] = raw.split(':');
    const seat = Number(seatText);
    if (!itemId || !known.has(itemId) || !Number.isInteger(seat) || seat < 1) {
      throw apiError(400, 'INVALID_ASSIGNMENT', `Bad item assignment "${raw}"`);
    }
    out.set(itemId, [...(out.get(itemId) ?? []), seat]);
  }
  return out;
}
