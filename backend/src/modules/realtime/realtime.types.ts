/** Event envelope emitted by the realtime service (PLAN.md 1.7 Realtime). */
export type RealtimeEvent = {
  scope: 'outlet' | 'station' | 'user';
  outletId?: string;
  station?: string;
  userId?: string;
  event: string;
  payload: unknown;
};
