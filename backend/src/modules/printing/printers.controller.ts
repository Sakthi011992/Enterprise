import { Body, Controller, Delete, Get, Param, Patch, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreatePrinterDto, UpdatePrinterDto, UpdateStationRoutesDto } from './dto/printing.dto';
import { PrintersService } from './printers.service';

@ApiTags('hardware')
@ApiBearerAuth()
@Controller()
export class PrintersController {
  constructor(private readonly printers: PrintersService) {}

  @Get('printers')
  @Can('admin.settings', 'VIEW')
  @ApiOperation({ summary: 'Printers of the current outlet' })
  list(@CurrentUser() auth: AuthUser) {
    return this.printers.list(auth);
  }

  @Post('printers')
  @Can('admin.settings', 'EDIT')
  create(@Body() dto: CreatePrinterDto, @CurrentUser() auth: AuthUser) {
    return this.printers.create(dto, auth);
  }

  @Patch('printers/:id')
  @Can('admin.settings', 'EDIT')
  update(@Param('id') id: string, @Body() dto: UpdatePrinterDto, @CurrentUser() auth: AuthUser) {
    return this.printers.update(id, dto, auth);
  }

  @Delete('printers/:id')
  @Can('admin.settings', 'EDIT')
  @ApiOperation({ summary: 'Deactivate a printer' })
  remove(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.printers.remove(id, auth);
  }

  @Post('printers/:id/test')
  @Can('admin.settings', 'EDIT')
  @ApiOperation({ summary: 'Queue a test page for this printer' })
  test(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.printers.test(id, auth);
  }

  @Get('station-routes')
  @Can('admin.settings', 'VIEW')
  routes(@CurrentUser() auth: AuthUser) {
    return this.printers.listRoutes(auth);
  }

  @Put('station-routes')
  @Can('admin.settings', 'EDIT')
  @ApiOperation({ summary: 'Replace the station to printer routing of the outlet' })
  replaceRoutes(@Body() dto: UpdateStationRoutesDto, @CurrentUser() auth: AuthUser) {
    return this.printers.replaceRoutes(dto, auth);
  }
}
