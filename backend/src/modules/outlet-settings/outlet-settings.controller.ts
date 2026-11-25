import { Body, Controller, Get, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { UpdateOutletSettingsDto } from './dto/outlet-settings.dto';
import { OutletSettingsService } from './outlet-settings.service';

@ApiTags('settings')
@ApiBearerAuth()
@Controller('outlet-settings')
export class OutletSettingsController {
  constructor(private readonly settings: OutletSettingsService) {}

  @Get()
  @Can('admin.settings', 'VIEW')
  get(@CurrentUser() auth: AuthUser) {
    return this.settings.get(auth);
  }

  @Put()
  @Can('admin.settings', 'EDIT')
  update(@Body() dto: UpdateOutletSettingsDto, @CurrentUser() auth: AuthUser) {
    return this.settings.update(dto, auth);
  }
}
