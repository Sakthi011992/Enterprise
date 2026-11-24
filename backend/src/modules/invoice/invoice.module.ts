import { Module } from '@nestjs/common';
import { InvoiceService } from './invoice.service';
import { InvoiceController } from './invoice.controller';
import { InvoiceNumberService } from './invoice-number.service';
import { InvoicePdfService } from './invoice-pdf.service';

@Module({
  controllers: [InvoiceController],
  providers: [InvoiceService, InvoiceNumberService, InvoicePdfService],
  exports: [InvoiceService],
})
export class InvoiceModule {}
