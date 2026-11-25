import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { OrdersService } from './orders.service';
import { CreateOrderDto, OrderQueryDto } from './dto/order.dto';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Can } from '../../common/decorators/can.decorator';

@ApiTags('orders')
@ApiBearerAuth()
@Controller('orders')
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  @Can('sales.orders.take', 'EDIT')
  @Post()
  @ApiOperation({ summary: 'Create an order (totals computed server-side)' })
  create(@Body() dto: CreateOrderDto, @CurrentUser('userId') userId: string) {
    return this.orders.create(dto, userId);
  }

  @Can('sales.orders.take', 'VIEW')
  @Get()
  @ApiOperation({ summary: 'Search order history' })
  findAll(@Query() q: OrderQueryDto) {
    return this.orders.findAll(q);
  }

  @Can('sales.orders.take', 'VIEW')
  @Get(':id')
  @ApiOperation({ summary: 'Order detail with items + payments' })
  findOne(@Param('id') id: string) {
    return this.orders.findOne(id);
  }
}
