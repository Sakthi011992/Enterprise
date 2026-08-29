import { ApiProperty } from '@nestjs/swagger';

export class DailyStatsEntity {
  @ApiProperty() ordersCount: number;
  @ApiProperty() revenue: number;
  @ApiProperty() taxCollected: number;
}

export class MonthlyStatsEntity {
  @ApiProperty() revenue: number;
  @ApiProperty() taxCollected: number;
}

export class DashboardEntity {
  @ApiProperty({ type: DailyStatsEntity }) today: DailyStatsEntity;
  @ApiProperty({ type: MonthlyStatsEntity }) monthly: MonthlyStatsEntity;
}

export class TopProductEntity {
  @ApiProperty() productId: string;
  @ApiProperty() productName: string;
  @ApiProperty() quantitySold: number;
  @ApiProperty() revenue: number;
}
