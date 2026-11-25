import { Module } from '@nestjs/common';
import { OutletsController } from './outlets.controller';
import { OutletsService } from './outlets.service';
import { OutletsRepository } from './outlets.repository';

@Module({
  controllers: [OutletsController],
  providers: [OutletsService, OutletsRepository],
  exports: [OutletsService],
})
export class OutletsModule {}
