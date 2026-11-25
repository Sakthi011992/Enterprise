import { Body, Controller, Delete, Get, Param, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import {
  CancelPurchaseOrderDto,
  PurchaseOrderDto,
  PurchaseOrdersQueryDto,
  ReorderRequestDto,
  ReorderSuggestionsQueryDto,
} from './dto/procurement.dto';
import { PurchaseOrdersService } from './purchase-orders.service';

/** Purchase orders and reorders (PLAN.md 1.6). Reorder routes are declared before ':id' so they are not read as ids. */
@ApiTags('procurement')
@ApiBearerAuth()
@Controller('purchase-orders')
export class PurchaseOrdersController {
  constructor(private readonly orders: PurchaseOrdersService) {}

  @Get()
  @Can('stock.purchaseOrders', 'VIEW')
  list(@Query() q: PurchaseOrdersQueryDto, @CurrentUser() auth: AuthUser) {
    return this.orders.list(q, auth);
  }

  @Get('reorder-suggestions')
  @Can('stock.purchaseOrders', 'VIEW')
  reorderSuggestions(@Query() q: ReorderSuggestionsQueryDto, @CurrentUser() auth: AuthUser) {
    return this.orders.reorderSuggestions(q, auth);
  }

  @Post('reorder-request')
  @Can('stock.purchaseOrders', 'REQUEST')
  reorderRequest(@Body() dto: ReorderRequestDto, @CurrentUser() auth: AuthUser) {
    return this.orders.reorderRequest(dto, auth);
  }

  @Get(':id')
  @Can('stock.purchaseOrders', 'VIEW')
  get(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.orders.get(id, auth);
  }

  @Post()
  @Can('stock.purchaseOrders', 'REQUEST')
  create(@Body() dto: PurchaseOrderDto, @CurrentUser() auth: AuthUser) {
    return this.orders.create(dto, auth);
  }

  @Put(':id')
  @Can('stock.purchaseOrders', 'REQUEST')
  update(@Param('id') id: string, @Body() dto: PurchaseOrderDto, @CurrentUser() auth: AuthUser) {
    return this.orders.update(id, dto, auth);
  }

  @Delete(':id')
  @Can('stock.purchaseOrders', 'REQUEST')
  remove(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.orders.remove(id, auth);
  }

  @Post(':id/submit')
  @Can('stock.purchaseOrders', 'REQUEST')
  submit(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.orders.submit(id, auth);
  }

  @Post(':id/approve')
  @Can('stock.purchaseOrders', 'APPROVE')
  approve(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.orders.approve(id, auth);
  }

  @Post(':id/send')
  @Can('stock.purchaseOrders', 'APPROVE')
  send(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.orders.send(id, auth);
  }

  @Post(':id/cancel')
  @Can('stock.purchaseOrders', 'APPROVE')
  cancel(@Param('id') id: string, @Body() dto: CancelPurchaseOrderDto, @CurrentUser() auth: AuthUser) {
    return this.orders.cancel(id, dto, auth);
  }
}
