/** Event envelope emitted by the realtime service (PLAN.md 1.7 Realtime). */
export type RealtimeEvent = {
  scope: 'outlet' | 'station' | 'user' | 'table';
  outletId?: string;
  station?: string;
  userId?: string;
  tableId?: string;
  event: string;
  payload: unknown;
};

/** Station name for the room that receives every station's events (all-stations KDS / expo screens). */
export const ALL_STATIONS = '*';

export const outletRoom = (outletId: string): string => `outlet:${outletId}`;

export const stationRoom = (outletId: string, station: string): string => `outlet:${outletId}:station:${station}`;

export const userRoom = (userId: string): string => `user:${userId}`;

/** Ids may be missing (e.g. a legacy order without an outlet); RealtimeService.publish skips such events. */
type MaybeId = string | null | undefined;

export const outletEvent = (outletId: MaybeId, event: string, payload: unknown): RealtimeEvent => ({
  scope: 'outlet',
  outletId: outletId ?? undefined,
  event,
  payload,
});

export const stationEvent = (outletId: MaybeId, station: MaybeId, event: string, payload: unknown): RealtimeEvent => ({
  scope: 'station',
  outletId: outletId ?? undefined,
  station: station ?? undefined,
  event,
  payload,
});

export const userEvent = (userId: MaybeId, event: string, payload: unknown): RealtimeEvent => ({
  scope: 'user',
  userId: userId ?? undefined,
  event,
  payload,
});

/** Room a guest socket joins (PLAN 2.6). Guests join this room and nothing else. */
export const tableRoom = (tableId: string): string => `table:${tableId}`;

export const tableEvent = (tableId: MaybeId, event: string, payload: unknown): RealtimeEvent => ({
  scope: 'table',
  tableId: tableId ?? undefined,
  event,
  payload,
});
