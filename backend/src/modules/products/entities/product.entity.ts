import { ApiProperty } from '@nestjs/swagger';

export class ProductEntity {
  @ApiProperty() id: string;
  @ApiProperty() name: string;
  @ApiProperty({ nullable: true }) description: string | null;
  @ApiProperty() price: string;
  @ApiProperty({ nullable: true }) taxPercentage: string | null;
  @ApiProperty({ nullable: true }) imageUrl: string | null;
  @ApiProperty() isActive: boolean;
  @ApiProperty() createdAt: Date;
  @ApiProperty() updatedAt: Date;
}

export class ProductsListEntity {
  @ApiProperty({ type: [ProductEntity] }) data: ProductEntity[];
  @ApiProperty() meta: Record<string, number>;
}

export class ImportSummaryEntity {
  @ApiProperty() created: number;
  @ApiProperty() updated: number;
  @ApiProperty() skipped: number;
  @ApiProperty({ type: [String] }) errors: string[];
}
