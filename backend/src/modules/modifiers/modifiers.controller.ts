import { Body, Controller, Delete, Get, Param, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { ModifierGroupDto } from './dto/modifier-group.dto';
import { ModifiersService } from './modifiers.service';

@ApiTags('menu')
@ApiBearerAuth()
@Controller('modifier-groups')
export class ModifiersController {
  constructor(private readonly modifiers: ModifiersService) {}

  @Get()
  @Can('menu.edit', 'VIEW')
  list() {
    return this.modifiers.list();
  }

  @Post()
  @Can('menu.edit', 'EDIT')
  create(@Body() dto: ModifierGroupDto) {
    return this.modifiers.create(dto);
  }

  @Put(':id')
  @Can('menu.edit', 'EDIT')
  update(@Param('id') id: string, @Body() dto: ModifierGroupDto) {
    return this.modifiers.update(id, dto);
  }

  @Delete(':id')
  @Can('menu.edit', 'EDIT')
  remove(@Param('id') id: string) {
    return this.modifiers.remove(id);
  }
}
