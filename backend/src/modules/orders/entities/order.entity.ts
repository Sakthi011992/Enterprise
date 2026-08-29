import { ApiProperty } from '@nestjs/swagger';

export class OrderItemEntity {
  @ApiProperty() id: string;
  @ApiProperty() productId: string;
  @ApiProperty() productName: string;
  @ApiProperty() price: string;
  @ApiProperty() quantity: number;
  @ApiProperty() taxPercentage: string;
  @ApiProperty() taxAmount: string;
  @ApiProperty() lineTotal: string;
}

export class OrderCashierEntity {
  @ApiProperty() username: string;
}

export class OrderEntity {
  @ApiProperty() id: string;
  @ApiProperty() invoiceNumber: string;
  @ApiProperty() subtotal: string;
  @ApiProperty() taxAmount: string;
  @ApiProperty() grandTotal: string;
  @ApiProperty() status: string;
  @ApiProperty() createdAt: Date;
  @ApiProperty({ type: OrderCashierEntity }) cashier: OrderCashierEntity;
  @ApiProperty({ type: [OrderItemEntity], required: false }) items?: OrderItemEntity[];
}

export class OrdersListEntity {
  @ApiProperty({ type: [OrderEntity] }) data: OrderEntity[];
  @ApiProperty() meta: Record<string, number>;
}
