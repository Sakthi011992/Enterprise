/** Local date/time parts of `date` in `timeZone`. */
function zonedParts(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  const value = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  return { year: value('year'), month: value('month'), day: value('day'), hour: value('hour'), minute: value('minute') };
}

/** The instant at which the wall clock in `timeZone` reads y-m-d h:mi. */
function zonedToInstant(year: number, month: number, day: number, hour: number, minute: number, timeZone: string): Date {
  const guess = Date.UTC(year, month - 1, day, hour, minute);
  const seen = zonedParts(new Date(guess), timeZone);
  const offset = Date.UTC(seen.year, seen.month - 1, seen.day, seen.hour, seen.minute) - guess;
  return new Date(guess - offset);
}

/** The first moment at or after `now` when the outlet clock shows `hhmm` ("20:00"). */
export function nextClockTime(now: Date, timeZone: string, hhmm: string): Date {
  const [hour, minute] = hhmm.split(':').map(Number);
  const local = zonedParts(now, timeZone);
  const today = zonedToInstant(local.year, local.month, local.day, hour, minute, timeZone);
  if (today.getTime() > now.getTime()) return today;
  const tomorrow = new Date(Date.UTC(local.year, local.month - 1, local.day + 1));
  return zonedToInstant(
    tomorrow.getUTCFullYear(),
    tomorrow.getUTCMonth() + 1,
    tomorrow.getUTCDate(),
    hour,
    minute,
    timeZone,
  );
}
