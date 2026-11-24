import {
  Body, Controller, Get, Param, Post, Query, Req, Res, UseGuards,
} from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Response, Request } from 'express';
import { InvoiceService } from './invoice.service';
import { GenerateInvoiceDto, AuditQueryDto } from './dto/invoice.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('invoices')
@Controller('invoices')
@UseGuards(JwtAuthGuard, RolesGuard)
export class InvoiceController {
  constructor(private svc: InvoiceService) {}

  @Roles('ADMIN', 'USER')
  @Post('generate')
  generate(@Body() dto: GenerateInvoiceDto, @CurrentUser('userId') userId: string) {
    return this.svc.generate(dto, userId);
  }

  @Roles('ADMIN')
  @Post(':id/void')
  void(@Param('id') id: string) {
    return this.svc.voidInvoice(id);
  }

  @Roles('ADMIN')
  @Get('audit')
  audit(@Query() q: AuditQueryDto) {
    return this.svc.findAudit(q);
  }

  @Roles('ADMIN', 'USER')
  @Get(':id/download')
  async download(
    @Param('id') id: string,
    @CurrentUser('userId') userId: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    const { buffer, invoiceNumber } = await this.svc.download(id, userId, req.ip);
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${invoiceNumber}.pdf"`);
    res.send(buffer);
  }

  @Roles('ADMIN')
  @Post('audit/export')
  bulkExport(@Body() body: { ids: string[] }) {
    return this.svc.bulkExport(body.ids);
  }
}
