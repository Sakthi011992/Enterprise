import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsIn, IsNumber, IsOptional, IsString, Length, Matches, Max, Min } from 'class-validator';

export const ORDER_TYPES = ['DINE_IN', 'BAR_COUNTER', 'TAKEAWAY', 'DELIVERY'] as const;
export const ROUNDING_MODES = ['NONE', 'NEAREST_1'] as const;

export class UpdateOutletSettingsDto {
  @ApiProperty({ example: 5 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(100)
  serviceChargePercent: number;

  @ApiProperty({ enum: ORDER_TYPES, isArray: true, example: ['DINE_IN'] })
  @IsArray()
  @ArrayMaxSize(4)
  @IsIn([...ORDER_TYPES], { each: true })
  serviceChargeTypes: (typeof ORDER_TYPES)[number][];

  @ApiProperty({ enum: ROUNDING_MODES })
  @IsIn([...ROUNDING_MODES])
  roundingMode: (typeof ROUNDING_MODES)[number];

  @ApiProperty({ example: 'A', description: 'Order number prefix, e.g. A-1043' })
  @Matches(/^[A-Z0-9]{1,8}$/, { message: 'orderPrefix: 1-8 upper case letters or digits' })
  orderPrefix: string;

  @ApiProperty({ example: 'INV', description: 'Invoice number prefix' })
  @Matches(/^[A-Z0-9]{1,8}$/, { message: 'invoicePrefix: 1-8 upper case letters or digits' })
  invoicePrefix: string;

  @ApiPropertyOptional({ example: 'IN', default: 'IN' })
  @IsOptional()
  @IsString()
  @Length(2, 2)
  countryCode?: string;
}
