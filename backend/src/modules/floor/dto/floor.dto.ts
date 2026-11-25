import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, Max, MaxLength, Min, MinLength } from 'class-validator';

export const TABLE_SHAPES = ['SQUARE', 'ROUND', 'LONG'] as const;
/** Statuses a staff member can set by hand. OCCUPIED and BILL_PRINTED come from orders. */
export const MANUAL_TABLE_STATUSES = ['FREE', 'CLEANING', 'RESERVED'] as const;

export class CreateAreaDto {
  @ApiProperty({ example: 'Rooftop' })
  @IsString()
  @MinLength(1)
  @MaxLength(60)
  name: string;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @ApiPropertyOptional({ example: 10, default: 0, description: 'Price markup for dine-in orders in this area' })
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(100)
  priceMarkupPercent?: number;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  isSmoking?: boolean;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class UpdateAreaDto extends PartialType(CreateAreaDto) {}

export class CreateTableDto {
  @ApiProperty()
  @IsString()
  areaId: string;

  @ApiProperty({ example: 'R4' })
  @IsString()
  @MinLength(1)
  @MaxLength(20)
  name: string;

  @ApiPropertyOptional({ default: 4 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  seats?: number;

  @ApiPropertyOptional({ enum: TABLE_SHAPES, default: 'SQUARE' })
  @IsOptional()
  @IsIn([...TABLE_SHAPES])
  shape?: (typeof TABLE_SHAPES)[number];

  @ApiPropertyOptional({ default: 0, description: 'Grid position on the floor plan' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(10000)
  posX?: number;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(10000)
  posY?: number;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class UpdateTableDto extends PartialType(CreateTableDto) {}

export class TableStatusDto {
  @ApiProperty({ enum: MANUAL_TABLE_STATUSES })
  @IsIn([...MANUAL_TABLE_STATUSES])
  status: (typeof MANUAL_TABLE_STATUSES)[number];
}
