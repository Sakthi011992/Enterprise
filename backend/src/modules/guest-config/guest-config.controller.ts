import { Body, Controller, Get, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { UpdateGuestConfigDto } from './dto/guest-config.dto';
import { GuestConfigService } from './guest-config.service';

@ApiTags('settings')
@ApiBearerAuth()
@Controller('settings/guest')
export class GuestConfigController {
  constructor(private readonly config: GuestConfigService) {}

  @Get()
  @Can('admin.settings', 'VIEW')
  get(@CurrentUser() auth: AuthUser) {
    return this.config.view(auth);
  }

  @Put()
  @Can('admin.settings', 'EDIT')
  update(@Body() dto: UpdateGuestConfigDto, @CurrentUser() auth: AuthUser) {
    return this.config.update(dto, auth);
  }
}
