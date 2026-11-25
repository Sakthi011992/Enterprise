import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { UsersService } from './users.service';
import { CreateUserDto, ResetPasswordDto, SetPinDto, SetUserOutletsDto, UpdateUserDto } from './dto/user.dto';
import { SetUserFeaturesDto } from './dto/user-features.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { PaginationDto } from '../../common/dto/pagination.dto';

@ApiTags('users')
@ApiBearerAuth()
@Roles('ADMIN')
@Can('admin.users', 'VIEW')
@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get()
  @ApiOperation({ summary: 'List users (paginated, searchable)' })
  findAll(@Query() q: PaginationDto, @CurrentUser() auth: AuthUser) {
    return this.users.findAll(q, auth);
  }

  @Get(':id')
  findOne(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.users.findOne(id, auth);
  }

  @Post()
  @Can('admin.users', 'EDIT')
  @ApiOperation({ summary: 'Create a user (assigned to the default outlet with a starting persona)' })
  create(@Body() dto: CreateUserDto, @CurrentUser() auth: AuthUser) {
    return this.users.create(dto, auth);
  }

  @Patch(':id')
  @Can('admin.users', 'EDIT')
  update(@Param('id') id: string, @Body() dto: UpdateUserDto, @CurrentUser() auth: AuthUser) {
    return this.users.update(id, dto, auth);
  }

  @Patch(':id/reset-password')
  @Can('admin.users', 'EDIT')
  @ApiOperation({ summary: 'Admin resets a user password' })
  resetPassword(@Param('id') id: string, @Body() dto: ResetPasswordDto, @CurrentUser() auth: AuthUser) {
    return this.users.resetPassword(id, dto.newPassword, auth);
  }

  @Patch(':id/pin')
  @Can('admin.users', 'EDIT')
  @ApiOperation({ summary: 'Set or reset the 4-digit staff PIN (clears any lock)' })
  setPin(@Param('id') id: string, @Body() dto: SetPinDto, @CurrentUser() auth: AuthUser) {
    return this.users.setPin(id, dto.pin, auth);
  }

  @Put(':id/outlets')
  @Can('admin.users', 'EDIT')
  @ApiOperation({ summary: 'Replace the outlet and persona assignments for a user' })
  setOutlets(@Param('id') id: string, @Body() dto: SetUserOutletsDto, @CurrentUser() auth: AuthUser) {
    return this.users.setOutlets(id, dto, auth);
  }

  @Delete(':id')
  @Can('admin.users', 'EDIT')
  @ApiOperation({ summary: 'Soft-delete a user' })
  remove(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.users.remove(id, auth);
  }

  @Get(':id/features')
  @ApiOperation({ summary: 'Get granted features for a user (deprecated: persona permissions replace this in Phase 2)' })
  getFeatures(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.users.getFeatures(id, auth);
  }

  @Put(':id/features')
  @Can('admin.users', 'EDIT')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Replace the full feature grant set for a user (deprecated)' })
  setFeatures(@Param('id') id: string, @Body() dto: SetUserFeaturesDto, @CurrentUser() auth: AuthUser) {
    return this.users.setFeatures(id, dto.features, auth);
  }
}
