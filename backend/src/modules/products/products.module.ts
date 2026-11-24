import { Module } from '@nestjs/common';
import { ProductsService } from './products.service';
import { ProductsController } from './products.controller';
import { ProductImportService } from './product-import.service';
import { ProductsRepository } from './products.repository';

@Module({
  controllers: [ProductsController],
  providers: [ProductsService, ProductsRepository, ProductImportService],
  exports: [ProductsService],
})
export class ProductsModule {}
