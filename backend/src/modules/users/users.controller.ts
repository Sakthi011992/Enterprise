import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { UsersService } from './users.service';
import { CreateUserDto, ResetPasswordDto, UpdateUserDto } from './dto/user.dto';
import { SetUserFeaturesDto } from './dto/user-features.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { PaginationDto } from '../../common/dto/pagination.dto';

@ApiTags('users')
@ApiBearerAuth()
@Roles('ADMIN')
@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get()
  @ApiOperation({ summary: 'List users (paginated, searchable)' })
  findAll(@Query() q: PaginationDto) {
    return this.users.findAll(q);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.users.findOne(id);
  }

  @Post()
  @ApiOperation({ summary: 'Create a user' })
  create(@Body() dto: CreateUserDto) {
    return this.users.create(dto);
  }

  @Patch(':id')
  update(@Param('id') id: string, @Body() dto: UpdateUserDto) {
    return this.users.update(id, dto);
  }

  @Patch(':id/reset-password')
  @ApiOperation({ summary: 'Admin resets a user password' })
  resetPassword(@Param('id') id: string, @Body() dto: ResetPasswordDto) {
    return this.users.resetPassword(id, dto.newPassword);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Soft-delete a user' })
  remove(@Param('id') id: string) {
    return this.users.remove(id);
  }

  @Get(':id/features')
  @ApiOperation({ summary: 'Get granted features for a user' })
  getFeatures(@Param('id') id: string) {
    return this.users.getFeatures(id);
  }

  @Put(':id/features')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Replace the full feature grant set for a user' })
  setFeatures(@Param('id') id: string, @Body() dto: SetUserFeaturesDto) {
    return this.users.setFeatures(id, dto.features);
  }
}
