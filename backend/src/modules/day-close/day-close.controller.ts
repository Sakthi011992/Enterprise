import { Body, Controller, Get, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { DayCloseService } from './day-close.service';
import { ZCloseDto } from './dto/day-close.dto';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';

/** X and Z reports. The dashboard endpoints stay in ReportsController. */
@ApiTags('reports')
@ApiBearerAuth()
@Controller('reports')
export class DayCloseController {
  constructor(private readonly dayClose: DayCloseService) {}

  @Can('reports.view', 'LIMITED')
  @Get('x')
  @ApiOperation({ summary: 'X report: live totals for the current business date (not saved)' })
  x(@CurrentUser() auth: AuthUser) {
    return this.dayClose.xReport(auth);
  }

  @Can('reports.view', 'LIMITED')
  @Post('x/print')
  @ApiOperation({ summary: 'Print the live X report on the receipt printer' })
  printX(@CurrentUser() auth: AuthUser) {
    return this.dayClose.printX(auth);
  }

  @Can('reports.view', 'EDIT')
  @Post('z')
  @ApiOperation({ summary: 'Z report: day close with cash counted' })
  z(@Body() dto: ZCloseDto, @CurrentUser() auth: AuthUser) {
    return this.dayClose.zClose(auth, dto);
  }

  @Can('reports.view', 'LIMITED')
  @Get('day-closes')
  @ApiOperation({ summary: 'Saved day closes of this outlet' })
  list(@CurrentUser() auth: AuthUser) {
    return this.dayClose.list(auth);
  }
}
