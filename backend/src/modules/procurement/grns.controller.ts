import { Body, Controller, Get, Param, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { DebitNotesQueryDto, GrnCreateDto, GrnUpdateDto, GrnsQueryDto } from './dto/procurement.dto';
import { DebitNotesService } from './debit-notes.service';
import { GrnsService } from './grns.service';

@ApiTags('procurement')
@ApiBearerAuth()
@Controller('grns')
export class GrnsController {
  constructor(private readonly grns: GrnsService) {}

  @Get()
  @Can('stock.purchaseOrders', 'VIEW')
  list(@Query() q: GrnsQueryDto, @CurrentUser() auth: AuthUser) {
    return this.grns.list(q, auth);
  }

  @Get(':id')
  @Can('stock.purchaseOrders', 'VIEW')
  get(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.grns.get(id, auth);
  }

  @Post()
  @Can('stock.purchaseOrders', 'REQUEST')
  create(@Body() dto: GrnCreateDto, @CurrentUser() auth: AuthUser) {
    return this.grns.create(dto, auth);
  }

  @Put(':id')
  @Can('stock.purchaseOrders', 'REQUEST')
  update(@Param('id') id: string, @Body() dto: GrnUpdateDto, @CurrentUser() auth: AuthUser) {
    return this.grns.update(id, dto, auth);
  }

  @Post(':id/post')
  @Can('stock.purchaseOrders', 'REQUEST')
  post(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.grns.post(id, auth);
  }
}

@ApiTags('procurement')
@ApiBearerAuth()
@Controller('debit-notes')
export class DebitNotesController {
  constructor(private readonly debitNotes: DebitNotesService) {}

  @Get()
  @Can('stock.purchaseOrders', 'VIEW')
  list(@Query() q: DebitNotesQueryDto, @CurrentUser() auth: AuthUser) {
    return this.debitNotes.list(q, auth);
  }

  @Post(':id/settle')
  @Can('stock.purchaseOrders', 'EDIT')
  settle(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.debitNotes.settle(id, auth);
  }
}
