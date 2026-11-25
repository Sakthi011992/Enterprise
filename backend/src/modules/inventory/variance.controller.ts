import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { VarianceQueryDto } from './dto/inventory.dto';
import { VarianceService } from './variance.service';

/** Variance report, kegs and the inventory summary. The variance and summary reads accept stock.count VIEW or reports.view LIMITED (checked in the service). */
@ApiTags('inventory')
@ApiBearerAuth()
@Controller('stock')
export class VarianceController {
  constructor(private readonly variance: VarianceService) {}

  @Get('variance')
  getVariance(@Query() q: VarianceQueryDto, @CurrentUser() auth: AuthUser) {
    return this.variance.variance(q, auth);
  }

  @Get('kegs')
  @Can('stock.count', 'VIEW')
  kegs(@CurrentUser() auth: AuthUser) {
    return this.variance.kegs(auth);
  }
}

@ApiTags('inventory')
@ApiBearerAuth()
@Controller('inventory')
export class InventorySummaryController {
  constructor(private readonly variance: VarianceService) {}

  @Get('summary')
  summary(@CurrentUser() auth: AuthUser) {
    return this.variance.summary(auth);
  }
}
