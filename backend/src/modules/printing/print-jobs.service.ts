import { Injectable } from '@nestjs/common';
import { Prisma, PrintJob } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { PrintingRepository } from './printing.repository';
import { PrintPayload } from './print-renderer';
import { PrintJobResultDto } from './dto/printing.dto';

/** Attempts before a job is marked FAILED. */
export const MAX_PRINT_ATTEMPTS = 3;
/** Jobs handed to one agent per poll. */
export const PRINT_BATCH_SIZE = 10;

/** Device types allowed to poll for and report print jobs. */
export const PRINT_DEVICE_TYPES = ['PRINTER', 'POS_TABLET'] as const;

export interface PrintDevice {
  id: string;
  tenantId: string;
  outletId: string;
  type: string;
}

export interface AgentJob {
  id: string;
  kind: PrintJob['kind'];
  printer: { host: string | null; port: number; paperWidth: number; copies: number };
  payload: PrintPayload;
}

/**
 * Decides what a failed job does next. Pure, so the retry and reroute rules are testable.
 * - A ticket job with a fallback printer (not the one that just failed) is requeued there, attempts reset.
 * - Otherwise attempts go up; below MAX_PRINT_ATTEMPTS the job is requeued, at the limit it is FAILED.
 */
export function nextAfterFailure(
  job: { attempts: number; printerId: string; ticketId: string | null },
  route: { fallbackPrinterId: string | null; fallbackUsable: boolean } | null,
): { status: 'QUEUED' | 'FAILED'; attempts: number; printerId: string; rerouted: boolean } {
  if (job.ticketId && route?.fallbackPrinterId && route.fallbackUsable && route.fallbackPrinterId !== job.printerId) {
    return { status: 'QUEUED', attempts: 0, printerId: route.fallbackPrinterId, rerouted: true };
  }
  const attempts = job.attempts + 1;
  return {
    status: attempts < MAX_PRINT_ATTEMPTS ? 'QUEUED' : 'FAILED',
    attempts,
    printerId: job.printerId,
    rerouted: false,
  };
}

export function assertPrintDevice(device: PrintDevice): void {
  if (!(PRINT_DEVICE_TYPES as readonly string[]).includes(device.type)) {
    throw apiError(403, 'DEVICE_TYPE_INVALID', 'This device cannot take print jobs');
  }
}

@Injectable()
export class PrintJobsService {
  constructor(private repo: PrintingRepository) {}

  /** Claims up to PRINT_BATCH_SIZE queued jobs for the device's outlet and returns them for printing. */
  async next(device: PrintDevice): Promise<AgentJob[]> {
    assertPrintDevice(device);
    const queued = await this.repo.findQueuedJobIds(device.outletId, PRINT_BATCH_SIZE);
    if (queued.length === 0) return [];

    const ids = queued.map((job) => job.id);
    await this.repo.markJobsSent(ids);
    const jobs = await this.repo.findJobsByIds(ids);

    const printers = await this.repo.findPrintersByIds([...new Set(jobs.map((job) => job.printerId))]);
    const byId = new Map(printers.map((p) => [p.id, p]));

    const out: AgentJob[] = [];
    for (const job of jobs) {
      const printer = byId.get(job.printerId);
      if (!printer || !printer.isActive || printer.outletId !== device.outletId) {
        await this.repo.updateJob(job.id, { status: 'FAILED', error: 'Printer is missing or inactive' });
        continue;
      }
      const payload = (job.payload ?? { lines: [], cut: false }) as unknown as PrintPayload;
      out.push({
        id: job.id,
        kind: job.kind,
        printer: {
          host: printer.host,
          port: printer.port,
          paperWidth: printer.paperWidth,
          copies: payload.copies ?? printer.copies,
        },
        payload,
      });
    }
    return out;
  }

  /** Agent reports the outcome of one job. Completes it, requeues it, reroutes a ticket or fails it. */
  async result(jobId: string, device: PrintDevice, dto: PrintJobResultDto) {
    assertPrintDevice(device);
    const job = await this.repo.findJob(jobId);
    if (!job || job.outletId !== device.outletId) throw apiError(404, 'PRINT_JOB_NOT_FOUND', 'Print job not found');
    if (job.status !== 'SENT') throw apiError(409, 'PRINT_JOB_NOT_IN_PROGRESS', 'This print job is not waiting for a result');

    if (dto.printerStatus) await this.repo.setPrinterStatus(job.printerId, dto.printerStatus);

    if (dto.ok) {
      await this.repo.updateJob(jobId, { status: 'DONE', doneAt: new Date(), error: null });
      if (job.ticketId) await this.repo.updateTicket(job.ticketId, { status: 'PRINTED', printedAt: new Date() });
      return { id: jobId, status: 'DONE' as const };
    }

    const error = dto.error ?? 'Printer did not accept the job';
    const ticket = job.ticketId ? await this.repo.findTicket(job.ticketId) : null;
    const route = ticket ? await this.repo.findRoute(job.outletId, ticket.station) : null;
    const fallback = route?.fallbackPrinterId ? (await this.repo.findPrintersByIds([route.fallbackPrinterId]))[0] : undefined;

    const decision = nextAfterFailure(job, {
      fallbackPrinterId: route?.fallbackPrinterId ?? null,
      fallbackUsable: !!fallback && fallback.isActive && fallback.outletId === job.outletId,
    });

    await this.repo.updateJob(jobId, {
      status: decision.status,
      attempts: decision.attempts,
      printerId: decision.printerId,
      error,
      ...(decision.status === 'FAILED' ? { doneAt: new Date() } : {}),
    } as Prisma.PrintJobUncheckedUpdateInput);

    if (decision.rerouted && ticket) {
      await this.repo.updateTicket(ticket.id, { printerId: decision.printerId });
      return { id: jobId, status: 'REROUTED' as const, printerId: decision.printerId };
    }

    if (decision.status === 'FAILED') {
      if (ticket) await this.repo.updateTicket(ticket.id, { status: 'FAILED' });
      const printer = await this.repo.findPrintersByIds([job.printerId]);
      const name = printer[0]?.name ?? 'Printer';
      await this.repo.createNotification({
        tenantId: job.tenantId,
        outletId: job.outletId,
        type: 'alert',
        title: `${name} failed`,
        body: `${error}. Check the printer and reprint from the Hardware screen.`,
        data: { printJobId: job.id, printerId: job.printerId },
      });
    }
    return { id: jobId, status: decision.status };
  }
}
