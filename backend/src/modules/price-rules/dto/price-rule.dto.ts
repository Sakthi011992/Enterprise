import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
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
} from 'class-validator';

export const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;

export class CreatePriceRuleDto {
  @ApiProperty({ example: 'Happy hour' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiPropertyOptional({ type: String, nullable: true, description: 'null = all outlets; otherwise the current outlet' })
  @IsOptional()
  @IsString()
  outletId?: string | null;

  @ApiProperty({ example: 30 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(100)
  percentOff: number;

  @ApiProperty({ type: [String], default: [] })
  @IsArray()
  @ArrayMaxSize(200)
  @ArrayUnique()
  @IsString({ each: true })
  categoryIds: string[];

  @ApiProperty({ type: [String], default: [] })
  @IsArray()
  @ArrayMaxSize(500)
  @ArrayUnique()
  @IsString({ each: true })
  productIds: string[];

  @ApiProperty({ type: [Number], example: [0, 1, 2, 3, 4, 5, 6], description: '0 = Sunday' })
  @IsArray()
  @ArrayMaxSize(7)
  @ArrayUnique()
  @IsInt({ each: true })
  @Min(0, { each: true })
  @Max(6, { each: true })
  days: number[];

  @ApiProperty({ example: '17:00', description: 'Outlet local time' })
  @Matches(TIME_PATTERN, { message: 'startTime must be HH:mm' })
  startTime: string;

  @ApiProperty({ example: '20:00', description: 'May be earlier than startTime for windows across midnight' })
  @Matches(TIME_PATTERN, { message: 'endTime must be HH:mm' })
  endTime: string;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class UpdatePriceRuleDto extends PartialType(CreatePriceRuleDto) {}
