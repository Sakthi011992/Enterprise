import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { DevicesService } from './devices.service';
import { CreateDeviceDto } from './dto/device.dto';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('devices')
@ApiBearerAuth()
@Controller('devices')
export class DevicesController {
  constructor(private readonly devices: DevicesService) {}

  @Get()
  @Can('admin.settings', 'VIEW')
  list(@CurrentUser() auth: AuthUser, @Query('outletId') outletId?: string) {
    return this.devices.list(auth, outletId);
  }

  @Post()
  @Can('admin.settings', 'EDIT')
  @ApiOperation({ summary: 'Register a device. The device key is shown only once' })
  create(@Body() dto: CreateDeviceDto, @CurrentUser() auth: AuthUser) {
    return this.devices.create(dto, auth);
  }

  @Delete(':id')
  @Can('admin.settings', 'EDIT')
  @ApiOperation({ summary: 'Deactivate a device' })
  remove(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.devices.deactivate(id, auth);
  }
}
