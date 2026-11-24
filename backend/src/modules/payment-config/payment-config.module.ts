import { Module } from '@nestjs/common';
import { PaymentConfigService } from './payment-config.service';
import { PaymentConfigController } from './payment-config.controller';

@Module({
  controllers: [PaymentConfigController],
  providers: [PaymentConfigService],
  exports: [PaymentConfigService],
})
export class PaymentConfigModule {}
