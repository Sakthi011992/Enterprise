import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

export const MODIFIER_CHANNELS = ['POS', 'QR', 'KIOSK'] as const;

export class ModifierOptionDto {
  @ApiPropertyOptional({ description: 'Existing option id; omit to create' })
  @IsOptional()
  @IsString()
  id?: string;

  @ApiProperty({ example: 'With soda' })
  @IsString()
  @MinLength(1)
  @MaxLength(80)
  name: string;

  @ApiPropertyOptional({ example: 40, default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(-10000)
  @Max(10000)
  priceDelta?: number;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @ApiPropertyOptional({ description: 'Stock item deducted when this option is sold (Phase 3)' })
  @IsOptional()
  @IsString()
  stockItemId?: string | null;

  @ApiPropertyOptional({ description: 'Base units of the stock item per option sold, e.g. 200 for a soda', example: 200 })
  @IsOptional()
  stockQty?: number | string | null;
}

/** Create and full update. PUT /modifier-groups/:id replaces the option list. */
export class ModifierGroupDto {
  @ApiProperty({ example: 'How to serve (spirits)' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  minSelect?: number;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(20)
  maxSelect?: number;

  @ApiPropertyOptional({ type: [String], default: ['POS'] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(3)
  @ArrayUnique()
  @IsIn([...MODIFIER_CHANNELS], { each: true })
  showOn?: (typeof MODIFIER_CHANNELS)[number][];

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @ApiProperty({ type: [ModifierOptionDto] })
  @IsArray()
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => ModifierOptionDto)
  options: ModifierOptionDto[];
}
