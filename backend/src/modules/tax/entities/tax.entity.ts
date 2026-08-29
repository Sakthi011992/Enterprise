import { ApiProperty } from '@nestjs/swagger';

export class GlobalTaxEntity {
  @ApiProperty() id: string;
  @ApiProperty() percentage: string;
  @ApiProperty() isActive: boolean;
  @ApiProperty() updatedAt: Date;
}

export class ProductTaxEntity {
  @ApiProperty() id: string;
  @ApiProperty() name: string;
  @ApiProperty({ nullable: true }) taxPercentage: string | null;
}
