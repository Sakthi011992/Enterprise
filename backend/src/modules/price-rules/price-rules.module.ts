import { Module } from '@nestjs/common';
import { PriceRulesController } from './price-rules.controller';
import { PriceRulesRepository } from './price-rules.repository';
import { PriceRulesService } from './price-rules.service';

@Module({
  controllers: [PriceRulesController],
  providers: [PriceRulesService, PriceRulesRepository],
  exports: [PriceRulesService],
})
export class PriceRulesModule {}
