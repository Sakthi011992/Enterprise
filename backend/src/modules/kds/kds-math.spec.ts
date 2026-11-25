import { allDayCounts, avgTicketSeconds, stationLabel, ticketColour, transitionError } from './kds-math';

const at = (iso: string) => new Date(iso);

describe('KDS math', () => {
  const created = at('2026-11-25T12:00:00Z');

  it('colours a ticket by age: green under 5 min, amber 5 to 10, red over 10', () => {
    expect(ticketColour(created, at('2026-11-25T12:04:59Z'))).toBe('green');
    expect(ticketColour(created, at('2026-11-25T12:05:00Z'))).toBe('amber');
    expect(ticketColour(created, at('2026-11-25T12:10:00Z'))).toBe('amber');
    expect(ticketColour(created, at('2026-11-25T12:10:01Z'))).toBe('red');
  });

  it('allows start only from NEW and bump from NEW or PREPARING', () => {
    expect(transitionError('start', 'NEW', null, created)).toBeNull();
    expect(transitionError('start', 'READY', null, created)).toBe('KDS_BAD_STATE');
    expect(transitionError('bump', 'PREPARING', null, created)).toBeNull();
    expect(transitionError('bump', 'SERVED', null, created)).toBe('KDS_BAD_STATE');
    expect(transitionError('served', 'PREPARING', null, created)).toBe('KDS_BAD_STATE');
    expect(transitionError('served', 'READY', null, created)).toBeNull();
  });

  it('recalls a READY ticket at once and a SERVED one only within 30 minutes', () => {
    expect(transitionError('recall', 'READY', null, created)).toBeNull();
    const servedAt = at('2026-11-25T12:00:00Z');
    expect(transitionError('recall', 'SERVED', servedAt, at('2026-11-25T12:30:00Z'))).toBeNull();
    expect(transitionError('recall', 'SERVED', servedAt, at('2026-11-25T12:30:01Z'))).toBe('RECALL_TOO_LATE');
    expect(transitionError('recall', 'NEW', null, created)).toBe('KDS_BAD_STATE');
  });

  it('averages creation-to-ready over bumped tickets only', () => {
    expect(
      avgTicketSeconds([
        { createdAt: at('2026-11-25T12:00:00Z'), readyAt: at('2026-11-25T12:04:00Z') },
        { createdAt: at('2026-11-25T12:00:00Z'), readyAt: at('2026-11-25T12:02:00Z') },
        { createdAt: at('2026-11-25T12:00:00Z'), readyAt: null },
      ]),
    ).toBe(180);
    expect(avgTicketSeconds([])).toBe(0);
  });

  it('all-day counts leave out served tickets and voided lines', () => {
    const lines = allDayCounts([
      { kdsStatus: 'READY', items: [{ name: 'Lager', variantName: null, quantity: 4, voided: false }, { name: 'Wings', variantName: null, quantity: 1, voided: true }] },
      { kdsStatus: 'NEW', items: [{ name: 'Lager', variantName: null, quantity: 2, voided: false }] },
      { kdsStatus: 'SERVED', items: [{ name: 'Lager', variantName: null, quantity: 9, voided: false }] },
    ]);
    expect(lines).toEqual([{ name: 'Lager', variantName: null, quantity: 6 }]);
  });

  it('labels stations for display', () => {
    expect(stationLabel('BAR')).toBe('Bar');
    expect(stationLabel('KITCHEN')).toBe('Kitchen');
  });
});
