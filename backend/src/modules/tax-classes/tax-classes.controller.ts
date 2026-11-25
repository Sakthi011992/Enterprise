import { Body, Controller, Delete, Get, Param, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { CreateTaxClassDto, UpdateTaxClassDto } from './dto/tax-class.dto';
import { TaxClassesService } from './tax-classes.service';

@ApiTags('tax')
@ApiBearerAuth()
@Controller('tax-classes')
export class TaxClassesController {
  constructor(private readonly taxClasses: TaxClassesService) {}

  @Get()
  @Can('admin.settings', 'VIEW')
  list() {
    return this.taxClasses.list();
  }

  @Post()
  @Can('admin.settings', 'EDIT')
  create(@Body() dto: CreateTaxClassDto) {
    return this.taxClasses.create(dto);
  }

  @Patch(':id')
  @Can('admin.settings', 'EDIT')
  update(@Param('id') id: string, @Body() dto: UpdateTaxClassDto) {
    return this.taxClasses.update(id, dto);
  }

  @Delete(':id')
  @Can('admin.settings', 'EDIT')
  remove(@Param('id') id: string) {
    return this.taxClasses.remove(id);
  }
}
