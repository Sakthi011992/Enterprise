import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { PaymentsService } from './payments.service';
import { CreatePaymentDto } from './dto/payment.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { Can } from '../../common/decorators/can.decorator';

@ApiTags('payments')
@ApiBearerAuth()
@Controller('payments')
export class PaymentsController {
  constructor(private readonly payments: PaymentsService) {}

  @Can('sales.payments.take', 'EDIT')
  @Post()
  @ApiOperation({ summary: 'Record a payment for an order' })
  create(@Body() dto: CreatePaymentDto) {
    return this.payments.create(dto);
  }

  @Can('sales.payments.take', 'VIEW')
  @Get('order/:orderId')
  @ApiOperation({ summary: 'List payments for an order' })
  byOrder(@Param('orderId') orderId: string) {
    return this.payments.findByOrder(orderId);
  }

  @Roles('ADMIN')
  @Can('sales.payments.take', 'EDIT')
  @Post(':id/refund')
  @ApiOperation({ summary: 'Refund a payment' })
  refund(@Param('id') id: string) {
    return this.payments.refund(id);
  }
}
