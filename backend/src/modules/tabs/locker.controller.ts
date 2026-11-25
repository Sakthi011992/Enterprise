import { Body, Controller, Delete, Get, Param, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreateLockerDto, LockerQueryDto, RemoveLockerDto, ServeLockerDto, UpdateLockerDto } from './dto/locker.dto';
import { LockerService } from './locker.service';

@ApiTags('locker')
@ApiBearerAuth()
@Controller('locker')
export class LockerController {
  constructor(private readonly locker: LockerService) {}

  @Can('sales.tab.open', 'VIEW')
  @Get()
  @ApiOperation({ summary: 'Bottle locker entries of the outlet' })
  list(@Query() q: LockerQueryDto, @CurrentUser() auth: AuthUser) {
    return this.locker.list(q, auth);
  }

  @Can('sales.tab.open', 'LIMITED')
  @Post()
  @ApiOperation({ summary: 'Store a partly used bottle for a guest' })
  create(@Body() dto: CreateLockerDto, @CurrentUser() auth: AuthUser) {
    return this.locker.create(dto, auth);
  }

  @Can('sales.tab.open', 'LIMITED')
  @Post(':id/serve')
  @ApiOperation({ summary: 'Serve ml from a stored bottle' })
  serve(@Param('id') id: string, @Body() dto: ServeLockerDto, @CurrentUser() auth: AuthUser) {
    return this.locker.serve(id, dto, auth);
  }

  @Can('sales.tab.open', 'LIMITED')
  @Put(':id')
  @ApiOperation({ summary: 'Edit guest details, expiry or remaining volume' })
  update(@Param('id') id: string, @Body() dto: UpdateLockerDto, @CurrentUser() auth: AuthUser) {
    return this.locker.update(id, dto, auth);
  }

  @Can('sales.tab.open', 'LIMITED')
  @Delete(':id')
  @ApiOperation({ summary: 'Remove a bottle from the locker (REMOVED)' })
  remove(@Param('id') id: string, @Body() dto: RemoveLockerDto, @CurrentUser() auth: AuthUser) {
    return this.locker.remove(id, dto, auth);
  }
}
