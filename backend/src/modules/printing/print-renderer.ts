import { Prisma } from '@prisma/client';

// Pure rendering of print payloads. The server renders structured lines; the print agent turns them
// into ESC/POS bytes (print-agent/src). Nothing in here touches Prisma or Nest.

export type LineAlign = 'left' | 'center' | 'right';

export interface PrintLine {
  text: string;
  bold?: boolean;
  align?: LineAlign;
  size?: 1 | 2;
}

/** Stored as PrintJob.payload (see PLAN 1.4). `copies` overrides the printer's copies for this job. */
export interface PrintPayload {
  lines: PrintLine[];
  cut: boolean;
  openDrawer?: boolean;
  copies?: number;
  reason?: string;
}

type Amount = Prisma.Decimal | string | number;

/** 58 mm paper prints 32 columns, 80 mm (and anything wider) 48 columns. */
export function columnsFor(paperWidth: number): number {
  return paperWidth === 58 ? 32 : 48;
}

/** 2 decimals with thousands separators, e.g. 1234.5 -> "1,234.50". */
export function formatAmount(value: Amount): string {
  const [whole, fraction] = new Prisma.Decimal(value).toFixed(2).split('.');
  const negative = whole.startsWith('-');
  const digits = negative ? whole.slice(1) : whole;
  return `${negative ? '-' : ''}${digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',')}.${fraction}`;
}

/** Left text on the left, right text flush right, within `width` columns. Truncates the left side if needed. */
export function twoColumn(left: string, right: string, width: number): string {
  const room = Math.max(0, width - right.length - 1);
  const shownLeft = left.length > room ? left.slice(0, room) : left;
  const gap = Math.max(1, width - shownLeft.length - right.length);
  return `${shownLeft}${' '.repeat(gap)}${right}`;
}

/** Word-wraps to `width` columns. Words longer than the width are split. Never returns an empty array. */
export function wrap(text: string, width: number): string[] {
  const words = text.replace(/\s+/g, ' ').trim().split(' ').filter((w) => w.length > 0);
  const out: string[] = [];
  let current = '';
  for (let word of words) {
    while (word.length > width) {
      if (current) {
        out.push(current);
        current = '';
      }
      out.push(word.slice(0, width));
      word = word.slice(width);
    }
    if (word.length === 0) continue;
    if (!current) current = word;
    else if (current.length + 1 + word.length <= width) current += ` ${word}`;
    else {
      out.push(current);
      current = word;
    }
  }
  if (current) out.push(current);
  return out.length > 0 ? out : [''];
}

export function divider(width: number): PrintLine {
  return { text: '-'.repeat(width) };
}

function wrapped(text: string, width: number, indent = '', extra: Partial<PrintLine> = {}): PrintLine[] {
  const usable = Math.max(1, width - indent.length);
  return wrap(text, usable).map((part) => ({ text: `${indent}${part}`, ...extra }));
}

export function receiptPayload(lines: PrintLine[], extra: Partial<PrintPayload> = {}): PrintPayload {
  return { lines, cut: true, ...extra };
}

// ---------------------------------------------------------------------------
// Kitchen / bar tickets (KOT / BOT)
// ---------------------------------------------------------------------------

export interface TicketPrintItem {
  quantity: number;
  name: string;
  variantName?: string | null;
  modifiers: string[];
  note?: string | null;
  seat?: number | null;
}

export interface TicketPrintData {
  kind: 'KOT' | 'BOT';
  seq: number;
  station: string;
  isCancellation: boolean;
  outletName: string;
  orderNumber: string;
  orderType: string;
  tableName: string | null;
  staffName: string | null;
  /** Already formatted in the outlet's time zone, e.g. "25 Nov 2026 18:40". */
  printedAt: string;
  items: TicketPrintItem[];
}

export function renderTicket(data: TicketPrintData, paperWidth: number): PrintPayload {
  const width = columnsFor(paperWidth);
  const lines: PrintLine[] = [];
  const title = `${data.isCancellation ? 'CANCEL ' : ''}${data.station} ${data.kind} #${data.seq}`;
  lines.push(...wrapped(title, width, '', { bold: true, align: 'center' }));
  if (data.isCancellation) lines.push({ text: '*** CANCELLED ITEMS ***', bold: true, align: 'center' });
  lines.push({ text: `${data.outletName}`, align: 'center' });
  lines.push(divider(width));
  lines.push(...wrapped(`Order ${data.orderNumber}${data.tableName ? `  Table ${data.tableName}` : ''}`, width, '', { bold: true }));
  lines.push({ text: `Type: ${data.orderType.replace('_', ' ')}` });
  if (data.staffName) lines.push({ text: `Staff: ${data.staffName}` });
  lines.push({ text: data.printedAt });
  lines.push(divider(width));

  for (const item of data.items) {
    const head = `${item.quantity} x ${item.name}${item.variantName ? ` (${item.variantName})` : ''}`;
    lines.push(...wrapped(head, width, '', { bold: true }));
    for (const modifier of item.modifiers) lines.push(...wrapped(`+ ${modifier}`, width, '   '));
    if (item.seat) lines.push({ text: `   Seat ${item.seat}` });
    if (item.note) lines.push(...wrapped(`NOTE: ${item.note}`, width, '   ', { bold: true }));
  }

  lines.push(divider(width));
  lines.push({ text: `Items: ${data.items.reduce((sum, i) => sum + i.quantity, 0)}`, align: 'right' });
  return receiptPayload(lines);
}

// ---------------------------------------------------------------------------
// Bill (pre-payment bill or tax invoice)
// ---------------------------------------------------------------------------

export interface BillPrintItem {
  quantity: number;
  name: string;
  variantName?: string | null;
  unitPrice: Amount;
  gross: Amount;
  modifiers: string[];
}

export interface BillPrintData {
  outletName: string;
  outletAddress?: string | null;
  orderNumber: string;
  invoiceNumber?: string | null;
  orderType: string;
  tableName: string | null;
  staffName: string | null;
  /** Already formatted in the outlet's time zone, e.g. "25 Nov 2026 18:40". */
  printedAt: string;
  items: BillPrintItem[];
  subtotal: Amount;
  discountTotal: Amount;
  serviceCharge: Amount;
  taxBreakdown: { name: string; rate: number | string; amount: Amount }[];
  roundOff: Amount;
  grandTotal: Amount;
  footer?: string;
}

export function renderBill(data: BillPrintData, paperWidth: number): PrintPayload {
  const width = columnsFor(paperWidth);
  const lines: PrintLine[] = [];
  lines.push({ text: data.outletName, bold: true, align: 'center' });
  if (data.outletAddress) lines.push(...wrapped(data.outletAddress, width, '', { align: 'center' }));
  lines.push({ text: data.invoiceNumber ? 'TAX INVOICE' : 'BILL', bold: true, align: 'center' });
  lines.push(divider(width));
  lines.push({ text: data.invoiceNumber ? `Invoice ${data.invoiceNumber}` : `Order ${data.orderNumber}` });
  if (data.invoiceNumber) lines.push({ text: `Order ${data.orderNumber}` });
  if (data.tableName) lines.push({ text: `Table ${data.tableName}` });
  lines.push({ text: `Type: ${data.orderType.replace('_', ' ')}` });
  if (data.staffName) lines.push({ text: `Staff: ${data.staffName}` });
  lines.push({ text: data.printedAt });
  lines.push(divider(width));

  for (const item of data.items) {
    const head = `${item.quantity} x ${item.name}`;
    lines.push(...wrapped(head, width - 10, '').map((part, index, all) =>
      index === all.length - 1 ? { text: twoColumn(part, formatAmount(item.gross), width) } : { text: part },
    ));
    if (item.variantName) lines.push({ text: `   ${item.variantName} @ ${formatAmount(item.unitPrice)}` });
    for (const modifier of item.modifiers) lines.push(...wrapped(`+ ${modifier}`, width, '   '));
  }

  lines.push(divider(width));
  lines.push({ text: twoColumn('Subtotal', formatAmount(data.subtotal), width) });
  if (new Prisma.Decimal(data.discountTotal).gt(0)) {
    lines.push({ text: twoColumn('Discount', `-${formatAmount(data.discountTotal)}`, width) });
  }
  if (new Prisma.Decimal(data.serviceCharge).gt(0)) {
    lines.push({ text: twoColumn('Service charge', formatAmount(data.serviceCharge), width) });
  }
  for (const tax of data.taxBreakdown) {
    lines.push({ text: twoColumn(`${tax.name} @ ${tax.rate}%`, formatAmount(tax.amount), width) });
  }
  if (!new Prisma.Decimal(data.roundOff).isZero()) {
    lines.push({ text: twoColumn('Round off', formatAmount(data.roundOff), width) });
  }
  lines.push(divider(width));
  lines.push({ text: twoColumn('TOTAL', formatAmount(data.grandTotal), width), bold: true });
  lines.push(divider(width));
  lines.push({ text: data.footer ?? 'Thank you, visit again', align: 'center' });
  return receiptPayload(lines);
}

// ---------------------------------------------------------------------------
// X and Z reports (DayClose totals, PLAN 1.6)
// ---------------------------------------------------------------------------

export interface ReportTotals {
  businessDate: string;
  orders?: { count?: number; paid?: number; void?: number; open?: number };
  gross?: Amount;
  discounts?: Amount;
  serviceCharge?: Amount;
  tax?: { name: string; rate: number | string; amount: Amount }[];
  roundOff?: Amount;
  net?: Amount;
  tips?: Amount;
  byPayment?: { method: string; count: number; amount: Amount }[];
  byType?: { type: string; count: number; amount: Amount }[];
  voids?: { count: number; amount: Amount };
  refunds?: { count: number; amount: Amount };
  discountsByStaff?: { name: string; amount: Amount }[];
  cashExpected?: Amount | null;
}

export interface ReportPrintData {
  kind: 'X' | 'Z';
  outletName: string;
  totals: ReportTotals;
  cashCounted?: Amount | null;
  /** Already formatted in the outlet's time zone, e.g. "25 Nov 2026 18:40". */
  printedAt: string;
}

export function renderReport(data: ReportPrintData, paperWidth: number): PrintPayload {
  const width = columnsFor(paperWidth);
  const t = data.totals;
  const money = (label: string, amount: Amount | undefined | null) =>
    ({ text: twoColumn(label, formatAmount(amount ?? 0), width) }) as PrintLine;
  const section = (title: string): PrintLine[] => [divider(width), { text: title, bold: true }];

  const lines: PrintLine[] = [
    { text: data.kind === 'Z' ? 'Z REPORT (DAY CLOSE)' : 'X REPORT (SHIFT)', bold: true, align: 'center' },
    { text: data.outletName, align: 'center' },
    { text: `Business date ${t.businessDate}`, align: 'center' },
    { text: data.printedAt, align: 'center' },
    ...section('Orders'),
    { text: twoColumn('Paid', String(t.orders?.paid ?? 0), width) },
    { text: twoColumn('Void', String(t.orders?.void ?? 0), width) },
    { text: twoColumn('Open', String(t.orders?.open ?? 0), width) },
    ...section('Sales'),
    money('Gross', t.gross),
    money('Discounts', t.discounts),
    money('Service charge', t.serviceCharge),
    ...(t.tax ?? []).map((tax) => ({ text: twoColumn(`${tax.name} @ ${tax.rate}%`, formatAmount(tax.amount), width) })),
    money('Round off', t.roundOff),
    money('Net sales', t.net),
    money('Tips', t.tips),
    ...section('By payment'),
    ...(t.byPayment ?? []).map((p) => ({ text: twoColumn(`${p.method} (${p.count})`, formatAmount(p.amount), width) })),
    ...section('By order type'),
    ...(t.byType ?? []).map((p) => ({ text: twoColumn(`${p.type} (${p.count})`, formatAmount(p.amount), width) })),
    ...section('Voids and refunds'),
    { text: twoColumn(`Voids (${t.voids?.count ?? 0})`, formatAmount(t.voids?.amount ?? 0), width) },
    { text: twoColumn(`Refunds (${t.refunds?.count ?? 0})`, formatAmount(t.refunds?.amount ?? 0), width) },
  ];

  if ((t.discountsByStaff ?? []).length > 0) {
    lines.push(...section('Discounts by staff'));
    for (const row of t.discountsByStaff ?? []) lines.push({ text: twoColumn(row.name, formatAmount(row.amount), width) });
  }

  if (data.kind === 'Z' || t.cashExpected !== undefined) {
    lines.push(...section('Cash'));
    lines.push(money('Expected', t.cashExpected ?? 0));
    if (data.cashCounted !== undefined && data.cashCounted !== null) {
      lines.push(money('Counted', data.cashCounted));
      const variance = new Prisma.Decimal(data.cashCounted).minus(t.cashExpected ?? 0);
      lines.push({ text: twoColumn('Variance', formatAmount(variance), width), bold: true });
    }
  }

  lines.push(divider(width));
  return receiptPayload(lines);
}

// ---------------------------------------------------------------------------
// Small payloads
// ---------------------------------------------------------------------------

export function renderTestPage(outletName: string, printerName: string, paperWidth: number, printedAt: string): PrintPayload {
  const width = columnsFor(paperWidth);
  return receiptPayload([
    { text: 'PRINTER TEST', bold: true, align: 'center' },
    { text: outletName, align: 'center' },
    { text: printerName, align: 'center' },
    divider(width),
    { text: `Paper width ${paperWidth} mm (${width} columns)` },
    { text: printedAt },
    divider(width),
    { text: 'If you can read this, the printer is set up.', align: 'center' },
  ]);
}

/** Cash drawer kick: no text, just the drawer pulse. */
export function renderDrawerKick(reason?: string): PrintPayload {
  return { lines: [], cut: false, openDrawer: true, ...(reason ? { reason } : {}) };
}

/** "25 Nov 2026, 18:40" in the outlet's time zone. */
export function formatOutletTime(value: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone,
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(value);
}
