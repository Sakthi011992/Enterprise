import { Module } from '@nestjs/common';
import { CombosController } from './combos.controller';
import { CombosRepository } from './combos.repository';
import { CombosService } from './combos.service';

@Module({
  controllers: [CombosController],
  providers: [CombosService, CombosRepository],
  exports: [CombosService],
})
export class CombosModule {}
