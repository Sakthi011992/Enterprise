import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { PaymentsService } from './payments.service';
import { CreatePaymentDto } from './dto/payment.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';

/** Legacy payment routes, kept for the old billing screen. */
@ApiTags('payments')
@ApiBearerAuth()
@Controller('payments')
export class PaymentsController {
  constructor(private readonly payments: PaymentsService) {}

  @Can('sales.payments.take', 'EDIT')
  @Post()
  @ApiOperation({ summary: 'Legacy: record one payment for an order' })
  create(@Body() dto: CreatePaymentDto, @CurrentUser() auth: AuthUser) {
    return this.payments.legacyCreate(dto, auth);
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
  @ApiOperation({ summary: 'Legacy: refund a payment (marks it and the order REFUNDED)' })
  refund(@Param('id') id: string) {
    return this.payments.legacyRefund(id);
  }
}
