// Time-zone helpers for the business-day window (5 am cut-off, outlet timezone).
// Pure: no Nest or Prisma imports. Used by P2-C orders (ticket sequence) and day close.

/** Business date as 'YYYY-MM-DD'. Accepts the string or a Date from businessDate(). */
export function toDateString(v: string | Date): string {
  return typeof v === 'string' ? v.slice(0, 10) : v.toISOString().slice(0, 10);
}

/** Offset of `timeZone` from UTC at `instant`, in milliseconds (positive east of UTC). */
function zoneOffsetMs(instant: Date, timeZone: string): number {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const parts = Object.fromEntries(dtf.formatToParts(instant).map((p) => [p.type, p.value]));
  const asUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour),
    Number(parts.minute),
    Number(parts.second),
  );
  return asUtc - (instant.getTime() - instant.getMilliseconds());
}

/** The instant at which the wall clock in `timeZone` reads `dateStr` at `hour`:00. */
export function instantAtLocalHour(dateStr: string, hour: number, timeZone: string): Date {
  const [y, m, d] = dateStr.split('-').map(Number);
  const wall = Date.UTC(y, m - 1, d, hour);
  let guess = wall - zoneOffsetMs(new Date(wall), timeZone);
  guess = wall - zoneOffsetMs(new Date(guess), timeZone);
  return new Date(guess);
}

export function addDays(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/** [start, end) of a business day: 05:00 local on `dateStr` until 05:00 local the next day. */
export function dayWindow(dateStr: string, timeZone: string): { start: Date; end: Date } {
  return {
    start: instantAtLocalHour(dateStr, 5, timeZone),
    end: instantAtLocalHour(addDays(dateStr, 1), 5, timeZone),
  };
}
