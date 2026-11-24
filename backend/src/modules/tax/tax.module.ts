import { Module } from '@nestjs/common';
import { TaxService } from './tax.service';
import { TaxController } from './tax.controller';
import { TaxRepository } from './tax.repository';

@Module({
  controllers: [TaxController],
  providers: [TaxService, TaxRepository],
  exports: [TaxService],
})
export class TaxModule {}
