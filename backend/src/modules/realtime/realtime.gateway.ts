import { Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { OnGatewayConnection, OnGatewayInit, WebSocketGateway } from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { GuestSocketAuthService } from './guest-socket-auth.service';
import { RealtimeService, RoomEmitter } from './realtime.service';
import { SocketAuthService } from './socket-auth.service';
import { outletRoom, stationRoom, tableRoom, userRoom } from './realtime.types';

/**
 * Socket.io gateway on the /rt namespace. The client sends its token and optional station list in `auth`
 * when it connects. A connection with a missing or invalid token is disconnected at once.
 *
 * - Staff token: joins its outlet room, its user room and one room per station.
 * - Guest token (`kind: 'guest'`, guest secret, open session): joins ONLY `table:<tableId>`. The station
 *   list is ignored, and the gateway has no message handlers, so no socket can join other rooms later.
 */
@WebSocketGateway({ namespace: '/rt', cors: { origin: true, credentials: true } })
export class RealtimeGateway implements OnGatewayInit, OnGatewayConnection {
  private readonly logger = new Logger(RealtimeGateway.name);

  constructor(
    private realtime: RealtimeService,
    private sockets: SocketAuthService,
    private guests: GuestSocketAuthService,
    private jwt: JwtService,
  ) {}

  afterInit(server: Server): void {
    this.realtime.attach(server as unknown as RoomEmitter);
  }

  /** Rooms the handshake may join. Throws when the token is refused. */
  async roomsFor(handshake: { token?: unknown; stations?: unknown }): Promise<string[]> {
    if (GuestSocketAuthService.looksLikeGuest(this.jwt, handshake.token)) {
      const guest = await this.guests.authenticate(handshake.token);
      return [tableRoom(guest.tableId)];
    }
    const { auth, stations } = await this.sockets.authenticate(handshake.token, handshake.stations);
    return [outletRoom(auth.outletId), userRoom(auth.userId), ...stations.map((s) => stationRoom(auth.outletId, s))];
  }

  async handleConnection(client: Socket): Promise<void> {
    const handshake = (client.handshake?.auth ?? {}) as { token?: unknown; stations?: unknown };
    try {
      const rooms = await this.roomsFor(handshake);
      for (const room of rooms) void client.join(room);
    } catch (e) {
      this.logger.debug(`Socket ${client.id} refused: ${(e as Error).message}`);
      client.disconnect(true);
    }
  }
}
