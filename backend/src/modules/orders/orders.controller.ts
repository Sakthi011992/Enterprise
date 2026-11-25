import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { OrdersService } from './orders.service';
import {
  AddItemsDto,
  BillDto,
  CreateOrderDto,
  DiscountDto,
  MergeOrderDto,
  MoveOrderDto,
  OrderQueryDto,
  TransferItemsDto,
  UpdateItemDto,
  VoidItemsDto,
  VoidOrderDto,
} from './dto/order.dto';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('orders')
@ApiBearerAuth()
@Controller('orders')
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  @Can('sales.orders.take', 'EDIT')
  @Post()
  @ApiOperation({ summary: 'Open an order (legacy body with items is a takeaway order)' })
  create(@Body() dto: CreateOrderDto, @CurrentUser() auth: AuthUser) {
    return this.orders.create(dto, auth);
  }

  @Can('sales.orders.take', 'VIEW')
  @Get()
  @ApiOperation({ summary: 'Search order history' })
  findAll(@Query() q: OrderQueryDto) {
    return this.orders.findAll(q);
  }

  // Declared before ':id' so "open" is not read as an id.
  @Can('sales.orders.take', 'VIEW')
  @Get('open')
  @ApiOperation({ summary: 'Open orders (OPEN, SENT, BILLED) of this outlet' })
  open(@CurrentUser() auth: AuthUser) {
    return this.orders.openOrders(auth);
  }

  @Can('sales.orders.take', 'VIEW')
  @Get(':id')
  @ApiOperation({ summary: 'Order view: lines, discounts, payments, totals' })
  findOne(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.orders.findOne(id, auth);
  }

  @Can('sales.orders.take', 'EDIT')
  @Post(':id/items')
  @ApiOperation({ summary: 'Add items to an order' })
  addItems(@Param('id') id: string, @Body() dto: AddItemsDto, @CurrentUser() auth: AuthUser) {
    return this.orders.addItems(id, dto, auth);
  }

  @Can('sales.orders.take', 'EDIT')
  @Patch(':id/items/:itemId')
  @ApiOperation({ summary: 'Change a line that has not been sent' })
  updateItem(
    @Param('id') id: string,
    @Param('itemId') itemId: string,
    @Body() dto: UpdateItemDto,
    @CurrentUser() auth: AuthUser,
  ) {
    return this.orders.updateItem(id, itemId, dto, auth);
  }

  @Can('sales.orders.take', 'EDIT')
  @Delete(':id/items/:itemId')
  @ApiOperation({ summary: 'Remove a line that has not been sent' })
  removeItem(@Param('id') id: string, @Param('itemId') itemId: string, @CurrentUser() auth: AuthUser) {
    return this.orders.removeItem(id, itemId, auth);
  }

  @Can('sales.orders.take', 'EDIT')
  @Post(':id/send')
  @ApiOperation({ summary: 'Send new lines to the kitchen and bar (KOT and BOT tickets)' })
  send(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.orders.send(id, auth);
  }

  @Can('sales.orders.take', 'EDIT')
  @Post(':id/hold')
  @ApiOperation({ summary: 'Hold the order' })
  hold(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.orders.setHold(id, true, auth);
  }

  @Can('sales.orders.take', 'EDIT')
  @Post(':id/unhold')
  @ApiOperation({ summary: 'Release a held order' })
  unhold(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.orders.setHold(id, false, auth);
  }

  @Can('sales.discount.give', 'REQUEST')
  @Post(':id/discounts')
  @ApiOperation({ summary: 'Apply a discount (above the limit it needs an approvalId)' })
  addDiscount(@Param('id') id: string, @Body() dto: DiscountDto, @CurrentUser() auth: AuthUser) {
    return this.orders.addDiscount(id, dto, auth);
  }

  @Can('sales.discount.give', 'EDIT')
  @Delete(':id/discounts/:discountId')
  @ApiOperation({ summary: 'Remove a discount' })
  removeDiscount(@Param('id') id: string, @Param('discountId') discountId: string, @CurrentUser() auth: AuthUser) {
    return this.orders.removeDiscount(id, discountId, auth);
  }

  @Can('sales.void', 'REQUEST')
  @Post(':id/void-items')
  @ApiOperation({ summary: 'Void lines (sent lines print a cancellation ticket and log wastage)' })
  voidItems(@Param('id') id: string, @Body() dto: VoidItemsDto, @CurrentUser() auth: AuthUser) {
    return this.orders.voidItems(id, dto, auth);
  }

  @Can('sales.void', 'REQUEST')
  @Post(':id/void')
  @ApiOperation({ summary: 'Void the whole order (only without payments)' })
  voidOrder(@Param('id') id: string, @Body() dto: VoidOrderDto, @CurrentUser() auth: AuthUser) {
    return this.orders.voidOrder(id, dto, auth);
  }

  @Can('sales.orders.take', 'EDIT')
  @Post(':id/move')
  @ApiOperation({ summary: 'Move a dine-in order to another table' })
  move(@Param('id') id: string, @Body() dto: MoveOrderDto, @CurrentUser() auth: AuthUser) {
    return this.orders.move(id, dto, auth);
  }

  @Can('sales.orders.take', 'EDIT')
  @Post(':id/merge')
  @ApiOperation({ summary: 'Merge another open order into this one' })
  merge(@Param('id') id: string, @Body() dto: MergeOrderDto, @CurrentUser() auth: AuthUser) {
    return this.orders.merge(id, dto, auth);
  }

  @Can('sales.orders.take', 'EDIT')
  @Post(':id/transfer-items')
  @ApiOperation({ summary: 'Move chosen lines to another order or a new table' })
  transferItems(@Param('id') id: string, @Body() dto: TransferItemsDto, @CurrentUser() auth: AuthUser) {
    return this.orders.transferItems(id, dto, auth);
  }

  @Can('sales.payments.take', 'VIEW')
  @Post(':id/bill')
  @HttpCode(200)
  @ApiOperation({ summary: 'Print the pre-payment bill' })
  bill(@Param('id') id: string, @Body() dto: BillDto, @CurrentUser() auth: AuthUser) {
    return this.orders.bill(id, dto, auth);
  }
}
