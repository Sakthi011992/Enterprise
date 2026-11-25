import { CostingMethod, StockLocationKind, StockUnit, WastageReason } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDefined,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { DecimalInput } from '../decimal-input';

export const LOCATION_KINDS: StockLocationKind[] = ['STORE', 'BAR', 'KITCHEN', 'CELLAR'];
export const STOCK_UNITS: StockUnit[] = ['ML', 'G', 'PC'];
export const COSTING_METHODS: CostingMethod[] = ['WEIGHTED_AVERAGE', 'FIFO'];
/** Reasons a user can log. VOID and DAMAGED_DELIVERY are written by the system only (PLAN.md 1.7). */
export const USER_WASTAGE_REASONS: WastageReason[] = [
  'BROKEN',
  'SPILLED',
  'EXPIRED',
  'COMP',
  'STAFF_MEAL',
  'BURNT',
  'DROPPED',
  'RETURNED',
  'OTHER',
];
export const ALL_WASTAGE_REASONS: WastageReason[] = [...USER_WASTAGE_REASONS, 'VOID', 'DAMAGED_DELIVERY'];
export const COUNT_STATUS_FILTERS = ['OPEN', 'SUBMITTED', 'POSTED', 'CANCELLED'] as const;
export const STOCK_STATUS_FILTERS = ['BELOW_PAR', 'VARIANCE', 'EXPIRES', 'NEGATIVE', 'OK'] as const;
export const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export class LocationDto {
  @IsString()
  @MinLength(1)
  @MaxLength(60)
  name: string;

  @IsIn(LOCATION_KINDS)
  kind: StockLocationKind;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @IsString({ each: true })
  stations?: string[];

  @IsOptional()
  @IsBoolean()
  isDefaultSales?: boolean;
}

export class OpeningDto {
  @IsString()
  locationId: string;

  @IsDefined()
  qty: DecimalInput;
}

export class StockItemDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  sku?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  categoryName?: string;

  @IsIn(STOCK_UNITS)
  baseUnit: StockUnit;

  @IsDefined()
  packSize: DecimalInput;

  @IsString()
  @MinLength(1)
  @MaxLength(20)
  packName: string;

  @IsString()
  @MinLength(1)
  @MaxLength(40)
  purchaseUnitName: string;

  @IsDefined()
  purchaseUnitQty: DecimalInput;

  @IsIn(COSTING_METHODS)
  costingMethod: CostingMethod;

  @IsOptional()
  @IsString()
  preferredVendorId?: string | null;

  @IsBoolean()
  isLiquor: boolean;

  @IsBoolean()
  isKeg: boolean;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(3650)
  shelfLifeDays?: number | null;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => OpeningDto)
  opening?: OpeningDto[];
}

export class ParLevelDto {
  @IsString()
  locationId: string;

  @IsDefined()
  parLevel: DecimalInput;
}

export class ParDto {
  @IsArray()
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => ParLevelDto)
  levels: ParLevelDto[];
}

export class ItemsQueryDto {
  @IsOptional()
  @IsString()
  locationId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  search?: string;

  @IsOptional()
  @IsIn(STOCK_STATUS_FILTERS)
  status?: (typeof STOCK_STATUS_FILTERS)[number];

  @IsOptional()
  @IsIn(['true', 'false'])
  liquor?: 'true' | 'false';
}

export class MovementsQueryDto {
  @IsOptional()
  @IsString()
  locationId?: string;

  @IsOptional()
  @Matches(DATE_PATTERN)
  from?: string;

  @IsOptional()
  @Matches(DATE_PATTERN)
  to?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(500)
  limit?: number;
}

export class DateRangeQueryDto {
  @IsOptional()
  @Matches(DATE_PATTERN)
  from?: string;

  @IsOptional()
  @Matches(DATE_PATTERN)
  to?: string;
}

export class TransferLineDto {
  @IsString()
  stockItemId: string;

  @IsDefined()
  qty: DecimalInput;
}

export class TransferDto {
  @IsString()
  fromLocationId: string;

  @IsString()
  toLocationId: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string;

  @IsArray()
  @ArrayMinSize(0)
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => TransferLineDto)
  lines: TransferLineDto[];
}

export class CountsQueryDto {
  @IsOptional()
  @IsIn(COUNT_STATUS_FILTERS)
  status?: (typeof COUNT_STATUS_FILTERS)[number];

  @IsOptional()
  @IsString()
  locationId?: string;
}

export class StartCountDto {
  @IsString()
  locationId: string;
}

export class CountLineDto {
  @IsString()
  stockItemId: string;

  @IsOptional()
  countedQty?: DecimalInput | null;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string | null;

  @IsOptional()
  @IsBoolean()
  confirmedOutlier?: boolean;

  @IsOptional()
  @IsString()
  countedAt?: string;
}

export class CountLinesDto {
  @IsArray()
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => CountLineDto)
  lines: CountLineDto[];
}

export class WastageQueryDto extends DateRangeQueryDto {
  @IsOptional()
  @IsString()
  locationId?: string;
}

export class WastageDto {
  @IsString()
  locationId: string;

  @IsString()
  stockItemId: string;

  @IsDefined()
  qty: DecimalInput;

  @IsIn(ALL_WASTAGE_REASONS)
  reason: WastageReason;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  photoUrl?: string;
}

export class VarianceQueryDto extends DateRangeQueryDto {
  @IsOptional()
  @IsString()
  locationId?: string;

  @IsOptional()
  @IsIn(['true', 'false'])
  liquor?: 'true' | 'false';
}
