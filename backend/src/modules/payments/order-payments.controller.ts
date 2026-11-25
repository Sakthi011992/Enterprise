import { Body, Controller, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { PaymentsService } from './payments.service';
import { PayOrderDto, RefundDto, SplitQueryDto } from './dto/payment.dto';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';

/** Order-scoped payment routes: pay, split, close, refund. */
@ApiTags('payments')
@ApiBearerAuth()
@Controller('orders')
export class OrderPaymentsController {
  constructor(private readonly payments: PaymentsService) {}

  @Can('sales.payments.take', 'VIEW')
  @Get(':id/split')
  @ApiOperation({ summary: 'Bill shares by equal parts, by seat or by item' })
  split(@Param('id') id: string, @Query() q: SplitQueryDto, @CurrentUser() auth: AuthUser) {
    return this.payments.split(id, q, auth);
  }

  @Can('sales.payments.take', 'EDIT')
  @Post(':id/payments')
  @ApiOperation({ summary: 'Take payment (split tender, tips, cash change)' })
  pay(@Param('id') id: string, @Body() dto: PayOrderDto, @CurrentUser() auth: AuthUser) {
    return this.payments.pay(id, dto, auth);
  }

  @Can('sales.payments.take', 'EDIT')
  @Post(':id/close')
  @HttpCode(200)
  @ApiOperation({ summary: 'Close a paid order (table to cleaning)' })
  close(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.payments.close(id, auth);
  }

  @Can('sales.payments.take', 'EDIT')
  @Post(':id/refund')
  @ApiOperation({ summary: 'Refund part or all of a paid order (manager approval unless APPROVE on sales.void)' })
  refund(@Param('id') id: string, @Body() dto: RefundDto, @CurrentUser() auth: AuthUser) {
    return this.payments.refund(id, dto, auth);
  }
}
