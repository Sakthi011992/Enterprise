/**
 * Business date for an outlet: the calendar date in the outlet's timezone, shifted back to the
 * previous day while the local time is before `dayStart` (default "05:00", PLAN 1.4, so a bar that closes at
 * 02:00 still belongs to the evening). Returns "YYYY-MM-DD".
 */
export function businessDateFor(now: Date, timeZone: string, dayStart = '05:00'): string {
  const { year, month, day, hour, minute } = localParts(now, timeZone);
  const startMinutes = parseHHMM(dayStart);
  const localMinutes = hour * 60 + minute;
  if (localMinutes >= startMinutes) return formatDate(year, month, day);
  // Before the day start: previous calendar day.
  const prev = new Date(Date.UTC(year, month - 1, day - 1));
  return formatDate(prev.getUTCFullYear(), prev.getUTCMonth() + 1, prev.getUTCDate());
}

/** "YYYY-MM-DD" to a Date at UTC midnight, the shape Prisma uses for `@db.Date`. */
export function toDateOnly(isoDate: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(isoDate)) throw new Error(`Invalid business date: ${isoDate}`);
  return new Date(`${isoDate}T00:00:00.000Z`);
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  let f = formatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
    formatters.set(timeZone, f);
  }
  return f;
}

export function localParts(now: Date, timeZone: string) {
  const parts = formatterFor(timeZone).formatToParts(now);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  return { year: get('year'), month: get('month'), day: get('day'), hour: get('hour'), minute: get('minute') };
}

export function parseHHMM(value: string): number {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(value);
  if (!m) throw new Error(`Invalid time "${value}", expected HH:MM`);
  return Number(m[1]) * 60 + Number(m[2]);
}

function formatDate(year: number, month: number, day: number): string {
  return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}
