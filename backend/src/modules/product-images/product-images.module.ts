import { Module } from '@nestjs/common';
import { ProductImagesService } from './product-images.service';
import { ProductImagesController, StockSearchController } from './product-images.controller';
import { UnsplashAdapter } from './adapters/unsplash.adapter';

@Module({
  controllers: [ProductImagesController, StockSearchController],
  providers: [ProductImagesService, UnsplashAdapter],
  exports: [ProductImagesService],
})
export class ProductImagesModule {}
