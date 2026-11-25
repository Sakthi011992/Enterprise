import { Injectable } from '@nestjs/common';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { PrintService } from './print.service';
import { CreatePrinterDto, UpdatePrinterDto, UpdateStationRoutesDto } from './dto/printing.dto';
import { PrintingRepository } from './printing.repository';

const IPV4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
const HOSTNAME = /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/;

/** An IPv4 address (each octet 0-255) or a plain hostname. */
export function isValidPrinterHost(host: string): boolean {
  const ipv4 = IPV4.exec(host);
  if (ipv4) return ipv4.slice(1).every((octet) => Number(octet) <= 255);
  return HOSTNAME.test(host);
}

/** Checks the connection rules: LAN printers need a valid host. */
export function assertPrinterConnection(connection: string, host: string | null | undefined): void {
  if (connection !== 'LAN') return;
  if (!host) throw apiError(400, 'PRINTER_HOST_REQUIRED', 'A LAN printer needs an IP address');
  if (!isValidPrinterHost(host)) throw apiError(400, 'PRINTER_HOST_INVALID', 'Enter a valid IP address or hostname');
}

@Injectable()
export class PrintersService {
  constructor(
    private repo: PrintingRepository,
    private print: PrintService,
  ) {}

  list(auth: AuthUser) {
    return this.repo.listPrinters(auth.outletId);
  }

  async create(dto: CreatePrinterDto, auth: AuthUser) {
    const connection = dto.connection ?? 'LAN';
    const host = dto.host ?? null;
    assertPrinterConnection(connection, host);
    return this.repo.createPrinter({
      tenantId: auth.tenantId,
      outletId: auth.outletId,
      name: dto.name,
      connection,
      host,
      port: dto.port ?? 9100,
      paperWidth: dto.paperWidth ?? 80,
      copies: dto.copies ?? 1,
      language: dto.language ?? 'en',
      isReceipt: dto.isReceipt ?? false,
      isActive: dto.isActive ?? true,
    });
  }

  async update(id: string, dto: UpdatePrinterDto, auth: AuthUser) {
    const printer = await this.repo.findPrinter(id, auth.outletId);
    if (!printer) throw apiError(404, 'PRINTER_NOT_FOUND', 'Printer not found');
    const next = {
      connection: dto.connection ?? printer.connection,
      host: dto.host !== undefined ? dto.host : printer.host,
    };
    assertPrinterConnection(next.connection, next.host);
    return this.repo.updatePrinter(id, {
      ...(dto.name !== undefined ? { name: dto.name } : {}),
      connection: next.connection,
      host: next.host,
      ...(dto.port !== undefined ? { port: dto.port } : {}),
      ...(dto.paperWidth !== undefined ? { paperWidth: dto.paperWidth } : {}),
      ...(dto.copies !== undefined ? { copies: dto.copies } : {}),
      ...(dto.language !== undefined ? { language: dto.language } : {}),
      ...(dto.isReceipt !== undefined ? { isReceipt: dto.isReceipt } : {}),
      ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
    });
  }

  /** Soft delete. Routes that still point at the printer skip it at print time (inactive printers are not used). */
  async remove(id: string, auth: AuthUser) {
    const printer = await this.repo.findPrinter(id, auth.outletId);
    if (!printer) throw apiError(404, 'PRINTER_NOT_FOUND', 'Printer not found');
    await this.repo.updatePrinter(id, { isActive: false, isReceipt: false });
    return { success: true };
  }

  test(id: string, auth: AuthUser) {
    return this.print.queueTest(id, auth.outletId);
  }

  async listRoutes(auth: AuthUser) {
    const rows = await this.repo.listRoutes(auth.outletId);
    return {
      items: rows.map((r) => ({ station: r.station, printerId: r.printerId, fallbackPrinterId: r.fallbackPrinterId })),
    };
  }

  async replaceRoutes(dto: UpdateStationRoutesDto, auth: AuthUser) {
    const stations = dto.items.map((i) => i.station);
    if (new Set(stations).size !== stations.length) {
      throw apiError(400, 'DUPLICATE_STATION', 'Each station can have only one route');
    }
    const ids = [...new Set(dto.items.flatMap((i) => [i.printerId, i.fallbackPrinterId]).filter((x): x is string => !!x))];
    if (ids.length > 0) {
      const printers = await this.repo.findPrintersByIds(ids);
      const valid = new Set(printers.filter((p) => p.outletId === auth.outletId).map((p) => p.id));
      if (ids.some((id) => !valid.has(id))) {
        throw apiError(400, 'PRINTER_NOT_IN_OUTLET', 'A printer on a route does not belong to this outlet');
      }
    }
    const rows = dto.items.map((i) => ({
      station: i.station,
      printerId: i.printerId ?? null,
      fallbackPrinterId: i.fallbackPrinterId ?? null,
    }));
    const saved = await this.repo.replaceRoutes(auth.tenantId, auth.outletId, rows);
    return {
      items: saved.map((r) => ({ station: r.station, printerId: r.printerId, fallbackPrinterId: r.fallbackPrinterId })),
    };
  }
}
