import { Injectable, Logger } from '@nestjs/common';
import { Prisma, Printer, PrintJob, Ticket } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import {
  BillPrintItem,
  PrintPayload,
  ReportTotals,
  formatOutletTime,
  renderBill,
  renderDrawerKick,
  renderReport,
  renderTestPage,
  renderTicket,
  TicketPrintItem,
} from './print-renderer';
import { PrintingRepository } from './printing.repository';

/** Ticket fields PrintService needs. P2-C passes the Ticket row it just created. */
export type TicketForPrint = Pick<
  Ticket,
  'id' | 'tenantId' | 'outletId' | 'orderId' | 'kind' | 'station' | 'seq' | 'isCancellation' | 'createdAt' | 'createdById'
> & { items: Prisma.JsonValue };

export interface RouteWithPrinters {
  printer: Printer | null | undefined;
  fallback: Printer | null | undefined;
}

/**
 * Primary printer if it exists, belongs to the outlet and is active; otherwise the fallback under the
 * same rule; otherwise null (the ticket cannot be printed).
 */
export function resolveRoutePrinter(route: RouteWithPrinters | null | undefined, outletId: string): Printer | null {
  const usable = (printer: Printer | null | undefined): Printer | null =>
    printer && printer.isActive && printer.outletId === outletId ? printer : null;
  if (!route) return null;
  return usable(route.printer) ?? usable(route.fallback);
}

/** Converts a rendered payload into the JSON value stored on PrintJob.payload. */
export function toJsonPayload(payload: PrintPayload): Prisma.InputJsonValue {
  return JSON.parse(JSON.stringify(payload)) as Prisma.InputJsonValue;
}

interface TicketItemJson {
  name: string;
  variantName?: string | null;
  quantity: number;
  modifiers?: string[];
  note?: string | null;
  seat?: number | null;
}

/**
 * Queues print jobs. Used by the orders module (P2-C) and by the printers controller (test prints).
 * Jobs are rendered here and picked up by the print agent through /print-jobs/next.
 */
@Injectable()
export class PrintService {
  private readonly logger = new Logger(PrintService.name);

  constructor(private repo: PrintingRepository) {}

  /** Sends a KOT/BOT (or cancellation) ticket to the printer routed to its station. Marks the ticket FAILED when no printer is routed. */
  async queueTicket(ticket: TicketForPrint): Promise<PrintJob | null> {
    const printer = await this.resolveStationPrinter(ticket.outletId, ticket.station);
    if (!printer) {
      this.logger.warn(`No printer for station ${ticket.station} at outlet ${ticket.outletId}; ticket ${ticket.id} not printed`);
      await this.repo.updateTicket(ticket.id, { status: 'FAILED' });
      return null;
    }

    const outlet = await this.repo.findOutlet(ticket.outletId);
    const header = await this.repo.findOrderHeader(ticket.orderId);
    const [table, users] = await Promise.all([
      this.repo.findTableName(header?.tableId ?? null),
      this.repo.findUsersByIds([ticket.createdById]),
    ]);
    const staff = users[0];

    const items: TicketPrintItem[] = (ticket.items as unknown as TicketItemJson[]).map((item) => ({
      quantity: item.quantity,
      name: item.name,
      variantName: item.variantName ?? null,
      modifiers: item.modifiers ?? [],
      note: item.note ?? null,
      seat: item.seat ?? null,
    }));

    const timeZone = outlet?.timezone ?? 'Asia/Kolkata';
    const payload = renderTicket(
      {
        kind: ticket.kind,
        seq: ticket.seq,
        station: ticket.station,
        isCancellation: ticket.isCancellation,
        outletName: outlet?.name ?? '',
        orderNumber: header?.orderNumber ?? '',
        orderType: header?.type ?? 'DINE_IN',
        tableName: table?.name ?? null,
        staffName: staff ? staff.displayName ?? staff.username : null,
        printedAt: formatOutletTime(ticket.createdAt, timeZone),
        items,
      },
      printer.paperWidth,
    );

    await this.repo.updateTicket(ticket.id, { printerId: printer.id });
    return this.repo.createJob({
      tenantId: ticket.tenantId,
      outletId: ticket.outletId,
      printerId: printer.id,
      kind: 'TICKET',
      payload: toJsonPayload(payload),
      ticketId: ticket.id,
    });
  }

  /** Pre-payment bill on the outlet's receipt printer. Throws 409 when there is no receipt printer. */
  async queueBill(orderId: string, opts: { copies?: number } = {}): Promise<PrintJob> {
    const order = await this.repo.findBillOrder(orderId);
    if (!order) throw apiError(404, 'ORDER_NOT_FOUND', 'Order not found');
    if (!order.outletId) throw apiError(409, 'ORDER_HAS_NO_OUTLET', 'Order is not linked to an outlet');

    const printer = await this.requireReceiptPrinter(order.outletId);
    const outlet = await this.repo.findOutlet(order.outletId);
    const [table, users] = await Promise.all([
      this.repo.findTableName(order.tableId),
      this.repo.findUsersByIds(order.waiterId ? [order.waiterId] : []),
    ]);

    const items: BillPrintItem[] = order.items
      .filter((item) => item.status !== 'VOIDED')
      .map((item) => ({
        quantity: item.quantity,
        name: item.productName,
        variantName: item.variantName ?? null,
        unitPrice: item.price,
        gross: item.grossAmount,
        modifiers: Array.isArray(item.modifiers) ? (item.modifiers as { name: string }[]).map((m) => m.name) : [],
      }));

    const timeZone = outlet?.timezone ?? 'Asia/Kolkata';
    const payload = renderBill(
      {
        outletName: outlet?.name ?? '',
        outletAddress: outlet?.address ?? null,
        orderNumber: order.orderNumber ?? '',
        invoiceNumber: order.invoiceNumber ?? null,
        orderType: order.type,
        tableName: table?.name ?? null,
        staffName: users[0] ? users[0].displayName ?? users[0].username : null,
        printedAt: formatOutletTime(new Date(), timeZone),
        items,
        subtotal: order.subtotal,
        discountTotal: order.discountTotal,
        serviceCharge: order.serviceCharge,
        taxBreakdown: Array.isArray(order.taxBreakdown)
          ? (order.taxBreakdown as unknown as { name: string; rate: number | string; amount: Prisma.Decimal | string }[])
          : [],
        roundOff: order.roundOff,
        grandTotal: order.grandTotal,
      },
      printer.paperWidth,
    );
    if (opts.copies) payload.copies = opts.copies;

    return this.repo.createJob({
      tenantId: order.tenantId,
      outletId: order.outletId,
      printerId: printer.id,
      kind: 'BILL',
      payload: toJsonPayload(payload),
    });
  }

  /** Z report for a saved day close. */
  async queueReport(dayCloseId: string): Promise<PrintJob> {
    const dayClose = await this.repo.findDayClose(dayCloseId);
    if (!dayClose) throw apiError(404, 'DAY_CLOSE_NOT_FOUND', 'Day close not found');
    return this.queueReportTotals(dayClose.outletId, {
      kind: dayClose.kind,
      totals: dayClose.totals as unknown as ReportTotals,
      cashCounted: dayClose.cashCounted,
      createdAt: dayClose.createdAt,
    });
  }

  /**
   * Prints a report from totals that are not saved (the live X report, or a Z report that has just been
   * written). Used by reports code that has no DayClose row for the X report.
   */
  async queueReportTotals(
    outletId: string,
    report: { kind: 'X' | 'Z'; totals: ReportTotals; cashCounted?: Prisma.Decimal | string | null; createdAt?: Date },
  ): Promise<PrintJob> {
    const printer = await this.requireReceiptPrinter(outletId);
    const outlet = await this.repo.findOutlet(outletId);
    const timeZone = outlet?.timezone ?? 'Asia/Kolkata';
    const payload = renderReport(
      {
        kind: report.kind,
        outletName: outlet?.name ?? '',
        totals: report.totals,
        cashCounted: report.cashCounted ?? null,
        printedAt: formatOutletTime(report.createdAt ?? new Date(), timeZone),
      },
      printer.paperWidth,
    );
    return this.repo.createJob({
      tenantId: printer.tenantId,
      outletId,
      printerId: printer.id,
      kind: 'REPORT',
      payload: toJsonPayload(payload),
    });
  }

  /**
   * Pulses the cash drawer through the receipt printer. Returns null (and logs) when the outlet has no
   * receipt printer, so a cash payment is never blocked by a hardware gap.
   */
  async openDrawer(outletId: string, reason: string): Promise<PrintJob | null> {
    const printer = await this.repo.findReceiptPrinter(outletId);
    if (!printer) {
      this.logger.warn(`Cash drawer not opened at outlet ${outletId}: no receipt printer (${reason})`);
      return null;
    }
    return this.repo.createJob({
      tenantId: printer.tenantId,
      outletId,
      printerId: printer.id,
      kind: 'DRAWER',
      payload: toJsonPayload(renderDrawerKick(reason)),
    });
  }

  /** Test page for one printer. Throws 404 when the printer is not in the outlet. */
  async queueTest(printerId: string, outletId: string): Promise<PrintJob> {
    const printer = await this.repo.findPrinter(printerId, outletId);
    if (!printer) throw apiError(404, 'PRINTER_NOT_FOUND', 'Printer not found');
    const outlet = await this.repo.findOutlet(outletId);
    const payload = renderTestPage(
      outlet?.name ?? '',
      printer.name,
      printer.paperWidth,
      formatOutletTime(new Date(), outlet?.timezone ?? 'Asia/Kolkata'),
    );
    return this.repo.createJob({
      tenantId: printer.tenantId,
      outletId,
      printerId: printer.id,
      kind: 'TEST',
      payload: toJsonPayload(payload),
    });
  }

  // ---- helpers -----------------------------------------------------------

  private async resolveStationPrinter(outletId: string, station: string): Promise<Printer | null> {
    const route = await this.repo.findRoute(outletId, station);
    if (!route) return null;
    const ids = [route.printerId, route.fallbackPrinterId].filter((id): id is string => !!id);
    const printers = ids.length > 0 ? await this.repo.findPrintersByIds(ids) : [];
    const byId = new Map(printers.map((p) => [p.id, p]));
    return resolveRoutePrinter(
      {
        printer: route.printerId ? byId.get(route.printerId) : null,
        fallback: route.fallbackPrinterId ? byId.get(route.fallbackPrinterId) : null,
      },
      outletId,
    );
  }

  private async requireReceiptPrinter(outletId: string): Promise<Printer> {
    const printer = await this.repo.findReceiptPrinter(outletId);
    if (!printer) throw apiError(409, 'NO_RECEIPT_PRINTER', 'No receipt printer is set up for this outlet');
    return printer;
  }
}
