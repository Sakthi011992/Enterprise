import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
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

export class TaxComponentDto {
  @ApiProperty({ example: 'CGST' })
  @IsString()
  @MinLength(1)
  @MaxLength(20)
  name: string;

  @ApiProperty({ example: 2.5 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(100)
  rate: number;
}

export class CreateTaxClassDto {
  @ApiProperty({ example: 'GST 5% (restaurant)' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiProperty({ example: 'GST5', description: 'Upper case code, unique per tenant' })
  @Matches(/^[A-Z][A-Z0-9_]{1,19}$/, { message: 'code must be upper case letters, digits or underscore' })
  code: string;

  @ApiProperty({ example: 5 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(100)
  rate: number;

  @ApiProperty({ type: [TaxComponentDto], example: [{ name: 'CGST', rate: 2.5 }, { name: 'SGST', rate: 2.5 }] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(6)
  @ValidateNested({ each: true })
  @Type(() => TaxComponentDto)
  components: TaxComponentDto[];

  @ApiPropertyOptional({ default: false, description: 'Prices already include this tax' })
  @IsOptional()
  @IsBoolean()
  inclusive?: boolean;

  @ApiPropertyOptional({ default: false, description: 'Liquor lines are never discounted' })
  @IsOptional()
  @IsBoolean()
  isLiquor?: boolean;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class UpdateTaxClassDto extends PartialType(CreateTaxClassDto) {}
