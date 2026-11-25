import { Body, Controller, Delete, Get, Param, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { CreateCategoryDto, UpdateCategoryDto } from './dto/category.dto';
import { CategoriesService } from './categories.service';

@ApiTags('menu')
@ApiBearerAuth()
@Controller('categories')
export class CategoriesController {
  constructor(private readonly categories: CategoriesService) {}

  @Get()
  @Can('menu.edit', 'VIEW')
  list() {
    return this.categories.list();
  }

  @Post()
  @Can('menu.edit', 'EDIT')
  create(@Body() dto: CreateCategoryDto) {
    return this.categories.create(dto);
  }

  @Patch(':id')
  @Can('menu.edit', 'EDIT')
  update(@Param('id') id: string, @Body() dto: UpdateCategoryDto) {
    return this.categories.update(id, dto);
  }

  @Delete(':id')
  @Can('menu.edit', 'EDIT')
  remove(@Param('id') id: string) {
    return this.categories.remove(id);
  }
}
