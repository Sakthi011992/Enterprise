import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

/** Data access for printers, station routes, print jobs and the rows the print service renders from. */
@Injectable()
export class PrintingRepository {
  constructor(private prisma: PrismaService) {}

  // ---- outlets -----------------------------------------------------------

  findOutlet(outletId: string) {
    return this.prisma.outlet.findFirst({ where: { id: outletId }, select: { id: true, name: true, address: true, timezone: true } });
  }

  // ---- printers ----------------------------------------------------------

  listPrinters(outletId: string) {
    return this.prisma.printer.findMany({ where: { outletId }, orderBy: { name: 'asc' } });
  }

  findPrinter(id: string, outletId: string) {
    return this.prisma.printer.findFirst({ where: { id, outletId } });
  }

  findPrintersByIds(ids: string[]) {
    return this.prisma.printer.findMany({ where: { id: { in: ids } } });
  }

  findReceiptPrinter(outletId: string) {
    return this.prisma.printer.findFirst({
      where: { outletId, isReceipt: true, isActive: true },
      orderBy: { name: 'asc' },
    });
  }

  createPrinter(data: Prisma.PrinterUncheckedCreateInput) {
    return this.prisma.printer.create({ data });
  }

  updatePrinter(id: string, data: Prisma.PrinterUncheckedUpdateInput) {
    return this.prisma.printer.update({ where: { id }, data });
  }

  setPrinterStatus(id: string, lastStatus: string) {
    return this.prisma.printer.update({ where: { id }, data: { lastStatus, lastSeenAt: new Date() } });
  }

  // ---- station routes ----------------------------------------------------

  listRoutes(outletId: string) {
    return this.prisma.stationRoute.findMany({ where: { outletId }, orderBy: { station: 'asc' } });
  }

  findRoute(outletId: string, station: string) {
    return this.prisma.stationRoute.findFirst({ where: { outletId, station } });
  }

  /** Replaces the outlet's routes: stations not in `rows` are removed, the rest are upserted. */
  async replaceRoutes(
    tenantId: string,
    outletId: string,
    rows: { station: string; printerId: string | null; fallbackPrinterId: string | null }[],
  ) {
    return this.prisma.$transaction(async (tx) => {
      await tx.stationRoute.deleteMany({
        where: { outletId, station: { notIn: rows.map((r) => r.station) } },
      });
      for (const row of rows) {
        await tx.stationRoute.upsert({
          where: { outletId_station: { outletId, station: row.station } },
          create: { tenantId, outletId, ...row },
          update: { printerId: row.printerId, fallbackPrinterId: row.fallbackPrinterId },
        });
      }
      return tx.stationRoute.findMany({ where: { outletId }, orderBy: { station: 'asc' } });
    });
  }

  // ---- orders, tickets and reports (read-only apart from ticket status) ----

  findOrderHeader(orderId: string) {
    return this.prisma.order.findFirst({
      where: { id: orderId },
      select: { id: true, outletId: true, orderNumber: true, type: true, tableId: true, waiterId: true },
    });
  }

  findTableName(tableId: string | null) {
    if (!tableId) return Promise.resolve(null);
    return this.prisma.diningTable.findFirst({ where: { id: tableId }, select: { name: true } });
  }

  findUsersByIds(ids: string[]) {
    return this.prisma.user.findMany({
      where: { id: { in: ids } },
      select: { id: true, displayName: true, username: true },
    });
  }

  findBillOrder(orderId: string) {
    return this.prisma.order.findFirst({
      where: { id: orderId },
      include: { items: { orderBy: { id: 'asc' } } },
    });
  }

  findDayClose(id: string) {
    return this.prisma.dayClose.findFirst({ where: { id } });
  }

  findTicket(id: string) {
    return this.prisma.ticket.findFirst({ where: { id } });
  }

  updateTicket(id: string, data: Prisma.TicketUncheckedUpdateInput) {
    return this.prisma.ticket.update({ where: { id }, data });
  }

  // ---- print jobs --------------------------------------------------------

  createJob(data: Prisma.PrintJobUncheckedCreateInput) {
    return this.prisma.printJob.create({ data });
  }

  findJob(id: string) {
    return this.prisma.printJob.findFirst({ where: { id } });
  }

  findQueuedJobIds(outletId: string, take: number) {
    return this.prisma.printJob.findMany({
      where: { outletId, status: 'QUEUED' },
      orderBy: { createdAt: 'asc' },
      take,
      select: { id: true },
    });
  }

  markJobsSent(ids: string[]) {
    return this.prisma.printJob.updateMany({ where: { id: { in: ids }, status: 'QUEUED' }, data: { status: 'SENT' } });
  }

  findJobsByIds(ids: string[]) {
    return this.prisma.printJob.findMany({ where: { id: { in: ids }, status: 'SENT' }, orderBy: { createdAt: 'asc' } });
  }

  updateJob(id: string, data: Prisma.PrintJobUncheckedUpdateInput) {
    return this.prisma.printJob.update({ where: { id }, data });
  }

  // ---- notifications -----------------------------------------------------

  createNotification(data: { tenantId: string; outletId: string; type: string; title: string; body?: string; data?: Prisma.InputJsonValue }) {
    return this.prisma.notification.create({ data: { ...data, body: data.body ?? null, data: data.data ?? Prisma.JsonNull } });
  }
}
