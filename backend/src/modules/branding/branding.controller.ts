import {
  Controller, Get, Param, Post, Query, Res, UploadedFile,
  UseGuards, UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiTags } from '@nestjs/swagger';
import { Response } from 'express';
import { LogoRole, LogoVariant } from '@prisma/client';
import { BrandingService } from './branding.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { Public } from '../../common/decorators/public.decorator';

@ApiTags('branding')
@Controller('branding')
@UseGuards(JwtAuthGuard, RolesGuard)
export class BrandingController {
  constructor(private svc: BrandingService) {}

  @Public()
  @Get(':themeId/logo')
  getLogo(
    @Param('themeId') themeId: string,
    @Query('role') role: LogoRole = LogoRole.WORDMARK,
    @Query('variant') variant: LogoVariant = LogoVariant.LIGHT,
  ) {
    return this.svc.getLogo(themeId, role, variant);
  }

  @Roles('ADMIN')
  @Get(':themeId/logos')
  listLogos(@Param('themeId') themeId: string) {
    return this.svc.listLogos(themeId);
  }

  @Roles('ADMIN')
  @Post(':themeId/logo')
  @UseInterceptors(FileInterceptor('file'))
  uploadLogo(
    @Param('themeId') themeId: string,
    @Query('role') role: LogoRole = LogoRole.WORDMARK,
    @Query('variant') variant: LogoVariant = LogoVariant.LIGHT,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return this.svc.uploadLogo(themeId, role, variant, file);
  }

  @Public()
  @Get('serve/:blobPath(*)')
  async serve(@Param('blobPath') blobPath: string, @Res() res: Response) {
    const { buffer, mimeType } = await this.svc.serveLogo(blobPath);
    res.setHeader('Content-Type', mimeType);
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    res.send(buffer);
  }
}
