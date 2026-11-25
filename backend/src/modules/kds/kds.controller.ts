import { Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { BoardQueryDto, ReadyQueryDto } from './dto/kds.dto';
import { KdsService } from './kds.service';

@ApiTags('kds')
@ApiBearerAuth()
@Controller('kds')
export class KdsController {
  constructor(private readonly kds: KdsService) {}

  @Can('kds.bump', 'VIEW')
  @Get('tickets')
  @ApiOperation({ summary: 'KDS board: active or done cards, all-day totals, average time to bump' })
  board(@Query() q: BoardQueryDto, @CurrentUser() auth: AuthUser) {
    return this.kds.board(q, auth);
  }

  @Can('kds.bump', 'EDIT')
  @Post('tickets/:id/start')
  @ApiOperation({ summary: 'Start a ticket (NEW to PREPARING)' })
  start(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.kds.start(id, auth);
  }

  @Can('kds.bump', 'EDIT')
  @Post('tickets/:id/bump')
  @ApiOperation({ summary: 'Bump a ticket to ready (NEW or PREPARING to READY); tells the waiter' })
  bump(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.kds.bump(id, auth);
  }

  @Can('kds.bump', 'EDIT')
  @Post('tickets/:id/recall')
  @ApiOperation({ summary: 'Recall a ready or recently served ticket to PREPARING' })
  recall(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.kds.recall(id, auth);
  }

  // No @Can: the service accepts sales.orders.take EDIT or kds.bump EDIT.
  @Post('tickets/:id/served')
  @ApiOperation({ summary: 'Mark a ready ticket served (READY to SERVED)' })
  served(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.kds.served(id, auth);
  }

  // No @Can: the service accepts sales.orders.take VIEW or kds.bump VIEW.
  @Get('ready')
  @ApiOperation({ summary: 'Ready items of the outlet (mine=true for the caller\'s tickets)' })
  ready(@Query() q: ReadyQueryDto, @CurrentUser() auth: AuthUser) {
    return this.kds.ready(q, auth);
  }

  @Can('kds.bump', 'VIEW')
  @Get('stations')
  @ApiOperation({ summary: 'Stations with their active card counts' })
  stations(@CurrentUser() auth: AuthUser) {
    return this.kds.stations(auth);
  }
}
