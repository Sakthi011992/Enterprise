import { Logger } from '@nestjs/common';
import { OnGatewayConnection, OnGatewayInit, WebSocketGateway } from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { RealtimeService, RoomEmitter } from './realtime.service';
import { SocketAuthService } from './socket-auth.service';
import { outletRoom, stationRoom, userRoom } from './realtime.types';

/**
 * Socket.io gateway on the /rt namespace. The client sends its access token and optional station list in
 * `auth` when it connects. A connection with a missing or invalid token is disconnected at once. Otherwise
 * the socket joins its outlet room, its user room and one room per station.
 */
@WebSocketGateway({ namespace: '/rt', cors: { origin: true, credentials: true } })
export class RealtimeGateway implements OnGatewayInit, OnGatewayConnection {
  private readonly logger = new Logger(RealtimeGateway.name);

  constructor(
    private realtime: RealtimeService,
    private sockets: SocketAuthService,
  ) {}

  afterInit(server: Server): void {
    this.realtime.attach(server as unknown as RoomEmitter);
  }

  async handleConnection(client: Socket): Promise<void> {
    const handshake = (client.handshake?.auth ?? {}) as { token?: unknown; stations?: unknown };
    try {
      const { auth, stations } = await this.sockets.authenticate(handshake.token, handshake.stations);
      void client.join(outletRoom(auth.outletId));
      void client.join(userRoom(auth.userId));
      for (const station of stations) void client.join(stationRoom(auth.outletId, station));
    } catch (e) {
      this.logger.debug(`Socket ${client.id} refused: ${(e as Error).message}`);
      client.disconnect(true);
    }
  }
}
