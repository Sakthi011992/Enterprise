import { ApiProperty } from '@nestjs/swagger';

export class PaymentEntity {
  @ApiProperty() id: string;
  @ApiProperty() orderId: string;
  @ApiProperty() amount: string;
  @ApiProperty() paymentMethod: string;
  @ApiProperty() status: string;
  @ApiProperty() createdAt: Date;
}

export class PaymentResultEntity {
  @ApiProperty({ type: PaymentEntity }) payment: PaymentEntity;
  @ApiProperty() order: Record<string, string>;
}
