import {
  Body, Controller, Get, Param, Post, Res, UploadedFile,
  UseGuards, UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Response } from 'express';
import { ApiTags } from '@nestjs/swagger';
import { LocalisationService } from './localisation.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { Public } from '../../common/decorators/public.decorator';

@ApiTags('localisation')
@Controller('locales')
@UseGuards(JwtAuthGuard, RolesGuard)
export class LocalisationController {
  constructor(private svc: LocalisationService) {}

  @Public()
  @Get(':locale/bundle')
  bundle(@Param('locale') locale: string) {
    return this.svc.getBundle(locale);
  }

  @Roles('ADMIN')
  @Post('keys')
  upsertKey(@Body() body: { key: string; description?: string }) {
    return this.svc.upsertKey(body.key, body.description);
  }

  @Roles('ADMIN')
  @Post(':locale/values')
  upsertValue(
    @Param('locale') locale: string,
    @Body() body: { key: string; value: string },
  ) {
    return this.svc.upsertValue(body.key, locale, body.value);
  }

  @Roles('ADMIN')
  @Get(':locale/export')
  async exportExcel(@Param('locale') locale: string, @Res() res: Response) {
    const buf = await this.svc.exportExcel(locale);
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="translations-${locale}.xlsx"`);
    res.send(buf);
  }

  @Roles('ADMIN')
  @Post(':locale/import')
  @UseInterceptors(FileInterceptor('file'))
  importExcel(
    @Param('locale') locale: string,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return this.svc.importExcel(file.buffer, locale);
  }
}
