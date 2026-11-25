import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsNumber, IsOptional, Min } from 'class-validator';

export class ZCloseDto {
  @ApiProperty({ example: 12450.5, description: 'Cash counted in the drawer' })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  cashCounted: number;

  @ApiPropertyOptional({ description: 'Close even when orders are still open (they stay unlinked)' })
  @IsOptional()
  @IsBoolean()
  force?: boolean;
}
