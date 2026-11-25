import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Put,
  Query,
  UploadedFile,
  UseInterceptors,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { CountLinesDto, CountsQueryDto, DateRangeQueryDto, StartCountDto, TransferDto, WastageDto, WastageQueryDto } from './dto/inventory.dto';
import { CountsService } from './counts.service';
import { MAX_STOCK_UPLOAD_BYTES, StockUploadsService } from './stock-uploads.service';
import { TransfersService } from './transfers.service';
import { WastageService } from './wastage.service';

/** Transfers, stock counts, wastage and photo uploads (PLAN.md 1.6 and 1.7). */
@ApiTags('inventory')
@ApiBearerAuth()
@Controller('stock')
export class StockOpsController {
  constructor(
    private readonly transfers: TransfersService,
    private readonly counts: CountsService,
    private readonly wastage: WastageService,
    private readonly uploads: StockUploadsService,
  ) {}

  @Get('transfers')
  @Can('stock.count', 'VIEW')
  listTransfers(@Query() q: DateRangeQueryDto, @CurrentUser() auth: AuthUser) {
    return this.transfers.list(q, auth);
  }

  @Post('transfers')
  @Can('stock.count', 'EDIT')
  createTransfer(@Body() dto: TransferDto, @CurrentUser() auth: AuthUser) {
    return this.transfers.create(dto, auth);
  }

  @Get('counts')
  @Can('stock.count', 'VIEW')
  listCounts(@Query() q: CountsQueryDto, @CurrentUser() auth: AuthUser) {
    return this.counts.list(q, auth);
  }

  @Post('counts')
  @Can('stock.count', 'EDIT')
  startCount(@Body() dto: StartCountDto, @CurrentUser() auth: AuthUser) {
    return this.counts.start(dto.locationId, auth);
  }

  @Get('counts/:id')
  @Can('stock.count', 'VIEW')
  getCount(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.counts.get(id, auth);
  }

  @Put('counts/:id/lines')
  @Can('stock.count', 'EDIT')
  saveCountLines(@Param('id') id: string, @Body() dto: CountLinesDto, @CurrentUser() auth: AuthUser) {
    return this.counts.saveLines(id, dto, auth);
  }

  @Post('counts/:id/submit')
  @Can('stock.count', 'EDIT')
  submitCount(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.counts.submit(id, auth);
  }

  @Post('counts/:id/post')
  @Can('stock.count', 'APPROVE')
  postCount(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.counts.post(id, auth);
  }

  @Post('counts/:id/cancel')
  @Can('stock.count', 'EDIT')
  cancelCount(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.counts.cancel(id, auth);
  }

  @Get('wastage')
  @Can('stock.count', 'VIEW')
  listWastage(@Query() q: WastageQueryDto, @CurrentUser() auth: AuthUser) {
    return this.wastage.list(q, auth);
  }

  @Post('wastage')
  @Can('stock.count', 'EDIT')
  logWastage(@Body() dto: WastageDto, @CurrentUser() auth: AuthUser) {
    return this.wastage.create(dto, auth);
  }

  @Post('uploads')
  @Can('stock.count', 'EDIT')
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_STOCK_UPLOAD_BYTES } }))
  upload(@UploadedFile() file: Express.Multer.File) {
    if (!file) throw new BadRequestException('File required');
    return this.uploads.upload(file);
  }
}
