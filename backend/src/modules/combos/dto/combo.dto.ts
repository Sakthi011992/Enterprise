import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { TIME_PATTERN } from '../../price-rules/dto/price-rule.dto';

export class ComboItemDto {
  @ApiProperty()
  @IsString()
  productId: string;

  @ApiPropertyOptional({ type: String, nullable: true, description: 'Variant of the product, if one is fixed' })
  @IsOptional()
  @IsString()
  variantId?: string | null;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(20)
  quantity?: number;

  @ApiPropertyOptional({ default: false, description: 'Guest may swap this item for another of the same category' })
  @IsOptional()
  @IsBoolean()
  swapAllowed?: boolean;
}

/** A combo is saved as a whole: PUT /combos/:id replaces the item list. */
export class ComboDto {
  @ApiProperty({ example: 'Beer bucket (5)' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiProperty({ example: 1200 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  price: number;

  @ApiPropertyOptional({ type: String, nullable: true })
  @IsOptional()
  @IsString()
  taxClassId?: string | null;

  @ApiPropertyOptional({ type: [Number], default: [0, 1, 2, 3, 4, 5, 6] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(7)
  @ArrayUnique()
  @IsInt({ each: true })
  @Min(0, { each: true })
  @Max(6, { each: true })
  days?: number[];

  @ApiPropertyOptional({ type: String, nullable: true, example: '17:00', description: 'null = all day' })
  @IsOptional()
  @Matches(TIME_PATTERN, { message: 'startTime must be HH:mm' })
  startTime?: string | null;

  @ApiPropertyOptional({ type: String, nullable: true, example: '23:59' })
  @IsOptional()
  @Matches(TIME_PATTERN, { message: 'endTime must be HH:mm' })
  endTime?: string | null;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @ApiProperty({ type: [ComboItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(20)
  @ValidateNested({ each: true })
  @Type(() => ComboItemDto)
  items: ComboItemDto[];
}
