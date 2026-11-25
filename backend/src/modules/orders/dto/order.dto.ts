import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsEnum,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { OrderType } from '@prisma/client';
import { PaginationDto } from '../../../common/dto/pagination.dto';

/** One line to add (AddItem in PLAN.md 1.4). Legacy carts send only productId and quantity. */
export class AddItemDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  productId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  comboId?: string;

  @ApiPropertyOptional({ description: 'Variant of the product, e.g. the 60 ml measure' })
  @IsOptional()
  @IsUUID()
  variantId?: string;

  @ApiProperty({ example: 2, minimum: 1 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(99)
  quantity: number;

  @ApiPropertyOptional({ minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  seat?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @IsUUID('all', { each: true })
  modifierOptionIds?: string[];
}

/**
 * POST /orders. The new shape sends `type`. The legacy billing screen sends only `items` with
 * productId and quantity; that body is treated as a TAKEAWAY order.
 */
export class CreateOrderDto {
  @ApiPropertyOptional({ enum: OrderType })
  @IsOptional()
  @IsEnum(OrderType)
  type?: OrderType;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  tableId?: string;

  @ApiPropertyOptional({ minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  covers?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  waiterId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;

  @ApiPropertyOptional({ description: 'Client-generated id; a repeated request returns the existing order' })
  @IsOptional()
  @IsString()
  @MinLength(8)
  @MaxLength(64)
  offlineId?: string;

  @ApiPropertyOptional({ type: [AddItemDto] })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => AddItemDto)
  items?: AddItemDto[];
}

export class AddItemsDto {
  @ApiProperty({ type: [AddItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => AddItemDto)
  items: AddItemDto[];
}

export class UpdateItemDto {
  @ApiPropertyOptional({ minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(99)
  quantity?: number;

  @ApiPropertyOptional({ minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  seat?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;

  @ApiPropertyOptional({ type: [String], description: 'Replaces the modifier selection' })
  @IsOptional()
  @IsArray()
  @IsUUID('all', { each: true })
  modifierOptionIds?: string[];
}

export class DiscountDto {
  @ApiProperty({ enum: ['PERCENT', 'FLAT'] })
  @IsIn(['PERCENT', 'FLAT'])
  type: 'PERCENT' | 'FLAT';

  @ApiProperty({ example: 20 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  value: number;

  @ApiPropertyOptional({ type: [String], description: 'Empty or missing = whole bill (liquor excluded)' })
  @IsOptional()
  @IsArray()
  @IsUUID('all', { each: true })
  itemIds?: string[];

  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  reason: string;

  @ApiPropertyOptional({ description: 'Approved DISCOUNT approval, needed above the discount limit' })
  @IsOptional()
  @IsUUID()
  approvalId?: string;
}

export class VoidItemsDto {
  @ApiProperty({ type: [String] })
  @IsArray()
  @ArrayMinSize(1)
  @IsUUID('all', { each: true })
  itemIds: string[];

  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  reason: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  approvalId?: string;
}

export class VoidOrderDto {
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  reason: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  approvalId?: string;
}

export class MoveOrderDto {
  @ApiProperty()
  @IsUUID()
  toTableId: string;

  @ApiPropertyOptional({ description: 'Seat the guests at a table smaller than the cover count' })
  @IsOptional()
  @IsBoolean()
  force?: boolean;
}

export class MergeOrderDto {
  @ApiProperty()
  @IsUUID()
  fromOrderId: string;
}

export class TransferItemsDto {
  @ApiProperty({ type: [String] })
  @IsArray()
  @ArrayMinSize(1)
  @IsUUID('all', { each: true })
  itemIds: string[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  toOrderId?: string;

  @ApiPropertyOptional({ description: 'Creates an order on this table when toOrderId is not given' })
  @IsOptional()
  @IsUUID()
  toTableId?: string;
}

export class BillDto {
  @ApiPropertyOptional({ minimum: 1, maximum: 5 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(5)
  copies?: number;
}

export class OrderQueryDto extends PaginationDto {
  @ApiPropertyOptional({ description: 'ISO date (orders on/after)' })
  @IsOptional()
  @IsString()
  from?: string;

  @ApiPropertyOptional({ description: 'ISO date (orders on/before)' })
  @IsOptional()
  @IsString()
  to?: string;
}
