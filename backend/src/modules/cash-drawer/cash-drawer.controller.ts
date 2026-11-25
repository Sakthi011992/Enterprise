import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CashDrawerService } from './cash-drawer.service';
import { OpenDrawerDto } from './dto/cash-drawer.dto';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('cash-drawer')
@ApiBearerAuth()
@Controller('cash-drawer')
export class CashDrawerController {
  constructor(private readonly drawer: CashDrawerService) {}

  // Anyone who takes orders may ask; the service checks sales.payments.take EDIT or a NO_SALE approval.
  @Can('sales.orders.take', 'EDIT')
  @Post('open')
  @HttpCode(200)
  @ApiOperation({ summary: 'No-sale cash drawer open (audited)' })
  open(@Body() dto: OpenDrawerDto, @CurrentUser() auth: AuthUser) {
    return this.drawer.open(auth, dto);
  }
}
