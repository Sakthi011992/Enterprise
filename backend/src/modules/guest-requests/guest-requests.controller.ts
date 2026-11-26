import { Body, Controller, Get, Header, Param, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { ConfirmRequestDto, RejectRequestDto } from './dto/guest-requests.dto';
import { GuestRequestsService } from './guest-requests.service';

@ApiTags('guest-requests')
@Controller()
export class GuestRequestsController {
  constructor(private svc: GuestRequestsService) {}

  @Get('guest-requests')
  @Can('guests.orders.confirm', 'VIEW')
  list(@CurrentUser() auth: AuthUser, @Query('status') status?: string, @Query('mine') mine?: string) {
    return this.svc.list(auth, status, mine);
  }

  @Post('guest-requests/:id/claim')
  @Can('guests.orders.confirm', 'EDIT')
  claim(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.svc.claim(id, auth);
  }

  @Post('guest-requests/:id/confirm')
  @Can('guests.orders.confirm', 'EDIT')
  confirm(@Param('id') id: string, @Body() dto: ConfirmRequestDto, @CurrentUser() auth: AuthUser) {
    return this.svc.confirm(id, dto, auth);
  }

  @Post('guest-requests/:id/reject')
  @Can('guests.orders.confirm', 'EDIT')
  reject(@Param('id') id: string, @Body() dto: RejectRequestDto, @CurrentUser() auth: AuthUser) {
    return this.svc.reject(id, dto, auth);
  }

  @Get('service-requests')
  @Can('sales.orders.take', 'VIEW')
  serviceRequests(@CurrentUser() auth: AuthUser, @Query('status') status?: string) {
    return this.svc.serviceRequests(auth, status);
  }

  @Post('service-requests/:id/ack')
  @Can('sales.orders.take', 'EDIT')
  ack(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.svc.ack(id, auth);
  }

  @Post('service-requests/:id/done')
  @Can('sales.orders.take', 'EDIT')
  done(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.svc.done(id, auth);
  }

  @Get('tables/qr-sheet')
  @Can('admin.settings', 'VIEW')
  @Header('Content-Type', 'text/html; charset=utf-8')
  @ApiOperation({ summary: 'Printable HTML sheet of table QR cards' })
  qrSheet(@CurrentUser() auth: AuthUser, @Query('areaId') areaId?: string) {
    return this.svc.qrSheet(auth, areaId);
  }

  @Get('tables/:id/guest-pin')
  @Can('sales.orders.take', 'VIEW')
  guestPin(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.svc.guestPin(id, auth);
  }

  @Post('tables/:id/qr/rotate')
  @Can('admin.settings', 'EDIT')
  rotate(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.svc.rotateQr(id, auth);
  }
}
