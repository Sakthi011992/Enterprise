import { Body, Controller, Delete, Get, Param, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { ComboDto } from './dto/combo.dto';
import { CombosService } from './combos.service';

@ApiTags('menu')
@ApiBearerAuth()
@Controller('combos')
export class CombosController {
  constructor(private readonly combos: CombosService) {}

  @Get()
  @Can('menu.edit', 'VIEW')
  list() {
    return this.combos.list();
  }

  @Post()
  @Can('menu.edit', 'EDIT')
  create(@Body() dto: ComboDto) {
    return this.combos.create(dto);
  }

  @Put(':id')
  @Can('menu.edit', 'EDIT')
  update(@Param('id') id: string, @Body() dto: ComboDto) {
    return this.combos.update(id, dto);
  }

  @Delete(':id')
  @Can('menu.edit', 'EDIT')
  remove(@Param('id') id: string) {
    return this.combos.remove(id);
  }
}
