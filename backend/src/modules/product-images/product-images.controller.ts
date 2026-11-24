import {
  Body, Controller, Delete, Get, Param, Patch, Post, Query, Res, UploadedFile,
  UseGuards, UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiTags } from '@nestjs/swagger';
import { Response } from 'express';
import { ProductImagesService } from './product-images.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { Public } from '../../common/decorators/public.decorator';

@ApiTags('product-images')
@Controller('products/:productId/images')
@UseGuards(JwtAuthGuard, RolesGuard)
export class ProductImagesController {
  constructor(private svc: ProductImagesService) {}

  @Public()
  @Get()
  list(@Param('productId') productId: string) {
    return this.svc.listImages(productId);
  }

  @Roles('ADMIN')
  @Post('upload')
  @UseInterceptors(FileInterceptor('file'))
  upload(
    @Param('productId') productId: string,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return this.svc.uploadImage(productId, file);
  }

  @Roles('ADMIN')
  @Post('stock')
  attachStock(
    @Param('productId') productId: string,
    @Body() body: {
      imageUrl: string;
      downloadLocation: string;
      photographerName: string;
      photographerUrl: string;
      sourceUrl: string;
    },
  ) {
    return this.svc.attachStock(productId, body);
  }

  @Roles('ADMIN')
  @Patch(':imageId/primary')
  setPrimary(
    @Param('productId') productId: string,
    @Param('imageId') imageId: string,
  ) {
    return this.svc.setPrimary(productId, imageId);
  }

  @Roles('ADMIN')
  @Delete(':imageId')
  deleteImage(@Param('imageId') imageId: string) {
    return this.svc.deleteImage(imageId);
  }
}

@ApiTags('product-images')
@Controller('product-images')
@UseGuards(JwtAuthGuard, RolesGuard)
export class StockSearchController {
  constructor(private svc: ProductImagesService) {}

  @Roles('ADMIN')
  @Get('stock-search')
  search(@Query('q') q: string, @Query('page') page = 1) {
    return this.svc.searchStock(q, Number(page));
  }

  @Public()
  @Get('serve/:blobPath(*)')
  async serve(@Param('blobPath') blobPath: string, @Res() res: Response) {
    const buffer = await this.svc.serveImage(blobPath);
    res.setHeader('Content-Type', 'image/webp');
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    res.send(buffer);
  }
}
