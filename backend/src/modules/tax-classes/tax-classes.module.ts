import { Module } from '@nestjs/common';
import { TaxClassesController } from './tax-classes.controller';
import { TaxClassesRepository } from './tax-classes.repository';
import { TaxClassesService } from './tax-classes.service';

@Module({
  controllers: [TaxClassesController],
  providers: [TaxClassesService, TaxClassesRepository],
  exports: [TaxClassesService],
})
export class TaxClassesModule {}
