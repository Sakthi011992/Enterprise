import { Body, Controller, Delete, Get, Param, Patch, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { PersonasService } from './personas.service';
import { CreatePersonaDto, SetPermissionsDto, UpdatePersonaDto } from './dto/persona.dto';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('personas')
@ApiBearerAuth()
@Controller('personas')
export class PersonasController {
  constructor(private readonly personas: PersonasService) {}

  @Get()
  @Can('admin.users', 'VIEW')
  @ApiOperation({ summary: 'List personas for this tenant' })
  list(@CurrentUser() auth: AuthUser) {
    return this.personas.list(auth);
  }

  @Post()
  @Can('admin.users', 'EDIT')
  @ApiOperation({ summary: 'Create a persona (optionally copying another matrix)' })
  create(@Body() dto: CreatePersonaDto, @CurrentUser() auth: AuthUser) {
    return this.personas.create(dto, auth);
  }

  @Patch(':id')
  @Can('admin.users', 'EDIT')
  update(@Param('id') id: string, @Body() dto: UpdatePersonaDto, @CurrentUser() auth: AuthUser) {
    return this.personas.update(id, dto, auth);
  }

  @Delete(':id')
  @Can('admin.users', 'EDIT')
  remove(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.personas.remove(id, auth);
  }

  @Get(':id/permissions')
  @Can('admin.users', 'VIEW')
  @ApiOperation({ summary: 'Permission matrix for a persona (every catalog key)' })
  getPermissions(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.personas.getPermissions(id, auth);
  }

  @Put(':id/permissions')
  @Can('admin.users', 'EDIT')
  @ApiOperation({ summary: 'Replace the permission matrix for a persona' })
  setPermissions(@Param('id') id: string, @Body() dto: SetPermissionsDto, @CurrentUser() auth: AuthUser) {
    return this.personas.setPermissions(id, dto, auth);
  }
}
