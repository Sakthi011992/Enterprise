import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { PaginationDto } from '../../../common/dto/pagination.dto';

export class CreateProductDto {
  @ApiProperty({ example: 'Coffee' })
  @IsString()
  @MaxLength(200)
  name: string;

  @ApiPropertyOptional({ example: 'Hot Coffee' })
  @IsOptional()
  @IsString()
  description?: string;

  @ApiProperty({ example: 100 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  price: number;

  @ApiPropertyOptional({ example: 5, description: 'null/omitted => use global tax' })
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  taxPercentage?: number;

  @ApiPropertyOptional({ type: String, nullable: true, description: 'Menu category' })
  @IsOptional()
  @IsString()
  categoryId?: string | null;

  @ApiPropertyOptional({ type: String, nullable: true, description: 'Overrides the category tax class' })
  @IsOptional()
  @IsString()
  taxClassId?: string | null;

  @ApiPropertyOptional({ example: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  sortOrder?: number;
}

export class UpdateProductDto extends PartialType(CreateProductDto) {}

export class UpdateStatusDto {
  @ApiProperty()
  @IsBoolean()
  isActive: boolean;
}

export class VariantItemDto {
  @ApiPropertyOptional({ description: 'Existing variant id; omit to create' })
  @IsOptional()
  @IsString()
  id?: string;

  @ApiProperty({ example: '60 ml' })
  @IsString()
  @MaxLength(60)
  name: string;

  @ApiProperty({ example: 340 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  price: number;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  sortOrder?: number;
}

/** PUT /products/:id/variants replaces the list. Variants left out are deactivated, not deleted (past orders keep them). */
export class ReplaceVariantsDto {
  @ApiProperty({ type: [VariantItemDto] })
  @IsArray()
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => VariantItemDto)
  items: VariantItemDto[];
}

export class SetModifierGroupsDto {
  @ApiProperty({ type: [String] })
  @IsArray()
  @ArrayMaxSize(20)
  @ArrayUnique()
  @IsString({ each: true })
  groupIds: string[];
}

export class Set86Dto {
  @ApiProperty()
  @IsBoolean()
  is86: boolean;
}

export class ProductQueryDto extends PaginationDto {
  @ApiPropertyOptional({ description: 'Filter by active state' })
  @IsOptional()
  @Transform(({ value }) => value === 'true' || value === true)
  @IsBoolean()
  isActive?: boolean;
}
