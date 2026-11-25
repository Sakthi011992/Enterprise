import { Body, Controller, Get, Param, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { OutletsService } from './outlets.service';
import { CreateOutletDto, UpdateOutletDto } from './dto/outlet.dto';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('outlets')
@ApiBearerAuth()
@Controller('outlets')
export class OutletsController {
  constructor(private readonly outlets: OutletsService) {}

  @Get()
  @ApiOperation({ summary: 'Outlets: all for admin.settings VIEW, otherwise only the caller\'s outlets' })
  list(@CurrentUser() auth: AuthUser) {
    return this.outlets.list(auth);
  }

  @Post()
  @Can('admin.settings', 'EDIT')
  create(@Body() dto: CreateOutletDto, @CurrentUser() auth: AuthUser) {
    return this.outlets.create(dto, auth);
  }

  @Patch(':id')
  @Can('admin.settings', 'EDIT')
  update(@Param('id') id: string, @Body() dto: UpdateOutletDto, @CurrentUser() auth: AuthUser) {
    return this.outlets.update(id, dto, auth);
  }
}
