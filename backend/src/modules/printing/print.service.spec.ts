import { Printer } from '@prisma/client';
import { PrintService, resolveRoutePrinter, TicketForPrint } from './print.service';
import { nextAfterFailure } from './print-jobs.service';

function printer(id: string, overrides: Partial<Printer> = {}): Printer {
  return {
    id,
    tenantId: 't1',
    outletId: 'o1',
    name: id,
    connection: 'LAN',
    host: '192.168.1.31',
    port: 9100,
    paperWidth: 80,
    copies: 1,
    language: 'en',
    isReceipt: false,
    isActive: true,
    lastStatus: null,
    lastSeenAt: null,
    ...overrides,
  } as Printer;
}

describe('station route printer resolution', () => {
  it('uses the primary printer when it is active', () => {
    const primary = printer('bar');
    const fallback = printer('spare');
    expect(resolveRoutePrinter({ printer: primary, fallback }, 'o1')?.id).toBe('bar');
  });

  it('falls back when the primary is inactive', () => {
    expect(resolveRoutePrinter({ printer: printer('bar', { isActive: false }), fallback: printer('spare') }, 'o1')?.id).toBe(
      'spare',
    );
  });

  it('falls back when there is no primary printer', () => {
    expect(resolveRoutePrinter({ printer: null, fallback: printer('spare') }, 'o1')?.id).toBe('spare');
  });

  it('ignores printers from another outlet', () => {
    expect(resolveRoutePrinter({ printer: printer('bar', { outletId: 'o2' }), fallback: null }, 'o1')).toBeNull();
  });

  it('returns null when nothing usable is routed', () => {
    expect(resolveRoutePrinter({ printer: null, fallback: null }, 'o1')).toBeNull();
    expect(resolveRoutePrinter(null, 'o1')).toBeNull();
  });
});

describe('PrintService.queueTicket routing', () => {
  const ticket: TicketForPrint = {
    id: 'tk-1',
    tenantId: 't1',
    outletId: 'o1',
    orderId: 'ord-1',
    kind: 'BOT',
    station: 'BAR',
    seq: 7,
    isCancellation: false,
    createdAt: new Date('2026-11-25T13:10:00Z'),
    createdById: 'u1',
    items: [{ orderItemId: 'oi-1', name: 'Premium Lager 650 ml', variantName: null, quantity: 2, modifiers: [], note: null, seat: 1 }],
  };

  function setup(printers: Printer[]) {
    const byId = new Map(printers.map((p) => [p.id, p]));
    const repo = {
      findRoute: jest.fn(async () => ({ printerId: 'bar', fallbackPrinterId: 'spare' })),
      findPrintersByIds: jest.fn(async (ids: string[]) => ids.map((id) => byId.get(id)).filter(Boolean)),
      findOutlet: jest.fn(async () => ({ name: 'Riverside Bar', timezone: 'Asia/Kolkata', address: null })),
      findOrderHeader: jest.fn(async () => ({ orderNumber: 'A-1043', type: 'DINE_IN', tableId: 't4' })),
      findTableName: jest.fn(async () => ({ name: 'R4' })),
      findUsersByIds: jest.fn(async () => [{ id: 'u1', displayName: 'Priya', username: 'priya' }]),
      updateTicket: jest.fn(async () => ({})),
      createJob: jest.fn(async (data: Record<string, unknown>) => ({ id: 'job-1', ...data })),
    };
    const service = new PrintService(repo as any);
    return { service, repo };
  }

  it('sends the ticket to the primary printer and renders it for that paper width', async () => {
    const { service, repo } = setup([printer('bar'), printer('spare')]);
    const job: any = await service.queueTicket(ticket);
    expect(job.printerId).toBe('bar');
    expect(job.kind).toBe('TICKET');
    expect(job.ticketId).toBe('tk-1');
    expect(repo.updateTicket).toHaveBeenCalledWith('tk-1', { printerId: 'bar' });
    const lines: { text: string }[] = job.payload.lines;
    expect(lines[0].text).toBe('BAR BOT #7');
    expect(lines.some((l) => l.text.includes('Premium Lager 650 ml'))).toBe(true);
    expect(job.payload.cut).toBe(true);
  });

  it('uses the fallback printer when the primary is inactive', async () => {
    const { service } = setup([printer('bar', { isActive: false }), printer('spare')]);
    const job: any = await service.queueTicket(ticket);
    expect(job.printerId).toBe('spare');
  });

  it('marks the ticket FAILED and queues nothing when no printer is usable', async () => {
    const { service, repo } = setup([printer('bar', { isActive: false }), printer('spare', { isActive: false })]);
    const job = await service.queueTicket(ticket);
    expect(job).toBeNull();
    expect(repo.updateTicket).toHaveBeenCalledWith('tk-1', { status: 'FAILED' });
    expect(repo.createJob).not.toHaveBeenCalled();
  });
});

describe('print job failure rules', () => {
  it('reroutes a failed ticket job to the fallback printer and resets attempts', () => {
    expect(
      nextAfterFailure({ attempts: 0, printerId: 'bar', ticketId: 'tk-1' }, { fallbackPrinterId: 'spare', fallbackUsable: true }),
    ).toEqual({ status: 'QUEUED', attempts: 0, printerId: 'spare', rerouted: true });
  });

  it('does not reroute when the failed printer is already the fallback', () => {
    expect(
      nextAfterFailure({ attempts: 0, printerId: 'spare', ticketId: 'tk-1' }, { fallbackPrinterId: 'spare', fallbackUsable: true }),
    ).toEqual({ status: 'QUEUED', attempts: 1, printerId: 'spare', rerouted: false });
  });

  it('requeues below three attempts and fails at three', () => {
    expect(nextAfterFailure({ attempts: 1, printerId: 'bar', ticketId: null }, null).status).toBe('QUEUED');
    expect(nextAfterFailure({ attempts: 2, printerId: 'bar', ticketId: null }, null)).toEqual({
      status: 'FAILED',
      attempts: 3,
      printerId: 'bar',
      rerouted: false,
    });
  });

  it('does not reroute a non-ticket job such as a bill', () => {
    expect(nextAfterFailure({ attempts: 0, printerId: 'receipt', ticketId: null }, { fallbackPrinterId: 'x', fallbackUsable: true }).rerouted).toBe(false);
  });
});
