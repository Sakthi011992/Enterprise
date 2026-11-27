import { Injectable, Logger } from '@nestjs/common';
import { ALL_STATIONS, RealtimeEvent, outletRoom, stationRoom, tableRoom, userRoom } from './realtime.types';

/** The part of a socket.io server or namespace that the service uses. */
export interface RoomEmitter {
  to(room: string): { emit(event: string, payload: unknown): unknown };
}

/**
 * Sends realtime messages to rooms. Services call it after their transaction has committed. Without a
 * server (unit tests, or before the gateway starts) every call is a logged no-op.
 */
@Injectable()
export class RealtimeService {
  private readonly logger = new Logger(RealtimeService.name);
  private server: RoomEmitter | null = null;

  /** Called by RealtimeGateway.afterInit with the /rt namespace. */
  attach(server: RoomEmitter | null): void {
    this.server = server;
  }

  get isReady(): boolean {
    return this.server !== null;
  }

  emitToOutlet(outletId: string, event: string, payload: unknown): void {
    this.send(outletRoom(outletId), event, payload);
  }

  /** Station screens get the event in their station room, and in the all-stations room. */
  emitToStation(outletId: string, station: string, event: string, payload: unknown): void {
    this.send(stationRoom(outletId, station), event, payload);
    this.send(stationRoom(outletId, ALL_STATIONS), event, payload);
  }

  /** Guest screens of one table. Only guest-safe payloads go here. */
  emitToTable(tableId: string, event: string, payload: unknown): void {
    this.send(tableRoom(tableId), event, payload);
  }

  emitToUser(userId: string, event: string, payload: unknown): void {
    this.send(userRoom(userId), event, payload);
  }

  /** Sends queued events in order. Events without the ids their scope needs are skipped. */
  publish(events: RealtimeEvent[]): void {
    for (const e of events) {
      if (e.scope === 'outlet' && e.outletId) this.emitToOutlet(e.outletId, e.event, e.payload);
      else if (e.scope === 'station' && e.outletId && e.station) this.emitToStation(e.outletId, e.station, e.event, e.payload);
      else if (e.scope === 'user' && e.userId) this.emitToUser(e.userId, e.event, e.payload);
      else if (e.scope === 'table' && e.tableId) this.emitToTable(e.tableId, e.event, e.payload);
      else this.logger.debug(`Skipped realtime event ${e.event}: scope ${e.scope} is missing its id`);
    }
  }

  private send(room: string, event: string, payload: unknown): void {
    if (!this.server) {
      this.logger.debug(`No realtime server; dropped ${event} for ${room}`);
      return;
    }
    this.server.to(room).emit(event, payload);
  }
}
