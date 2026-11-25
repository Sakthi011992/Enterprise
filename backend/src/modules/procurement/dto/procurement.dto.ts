import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
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
import { DecimalInput } from '../../inventory/decimal-input';

export const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
export const PO_STATUS_FILTERS = [
  'DRAFT',
  'PENDING_APPROVAL',
  'APPROVED',
  'SENT',
  'PARTLY_RECEIVED',
  'RECEIVED',
  'INVOICE_MISMATCH',
  'CANCELLED',
] as const;
export const DEBIT_NOTE_STATUS_FILTERS = ['OPEN', 'SETTLED', 'CANCELLED'] as const;

export class VendorDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  contactName?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  phone?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  email?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(15)
  gstin?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  address?: string | null;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(365)
  paymentTermsDays?: number;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class VendorsQueryDto {
  @IsOptional()
  @IsIn(['true', 'false'])
  active?: 'true' | 'false';
}

export class PurchaseOrdersQueryDto {
  @IsOptional()
  @IsIn(PO_STATUS_FILTERS)
  status?: (typeof PO_STATUS_FILTERS)[number];

  @IsOptional()
  @IsString()
  vendorId?: string;
}

export class PoLineDto {
  @IsString()
  stockItemId: string;

  @IsDefined()
  qty: DecimalInput;

  @IsDefined()
  rate: DecimalInput;
}

export class PurchaseOrderDto {
  @IsString()
  vendorId: string;

  @IsString()
  locationId: string;

  @IsOptional()
  @Matches(DATE_PATTERN)
  dueDate?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  transportPermitNo?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string | null;

  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => PoLineDto)
  lines: PoLineDto[];
}

export class CancelPurchaseOrderDto {
  @IsString()
  @MinLength(1)
  @MaxLength(300)
  reason: string;
}

export class ReorderSuggestionsQueryDto {
  @IsOptional()
  @IsString()
  locationId?: string;
}

export class ReorderLineDto {
  @IsString()
  stockItemId: string;

  @IsDefined()
  qty: DecimalInput;
}

export class ReorderRequestDto {
  @IsString()
  locationId: string;

  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => ReorderLineDto)
  lines: ReorderLineDto[];
}

export class GrnsQueryDto {
  @IsOptional()
  @Matches(DATE_PATTERN)
  from?: string;

  @IsOptional()
  @Matches(DATE_PATTERN)
  to?: string;

  @IsOptional()
  @IsString()
  vendorId?: string;
}

export class DebitNotesQueryDto {
  @IsOptional()
  @IsIn(DEBIT_NOTE_STATUS_FILTERS)
  status?: (typeof DEBIT_NOTE_STATUS_FILTERS)[number];
}

export class GrnLineDto {
  @IsOptional()
  @IsString()
  poLineId?: string | null;

  @IsString()
  stockItemId: string;

  @IsOptional()
  orderedQty?: DecimalInput;

  @IsOptional()
  invoicedQty?: DecimalInput;

  @IsOptional()
  receivedQty?: DecimalInput;

  @IsOptional()
  damagedQty?: DecimalInput;

  @IsDefined()
  rate: DecimalInput;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  batch?: string | null;

  @IsOptional()
  @Matches(DATE_PATTERN)
  expiry?: string | null;
}

export class GrnBaseDto {
  @IsOptional()
  @IsString()
  vendorId?: string;

  @IsOptional()
  @IsString()
  locationId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  vendorInvoiceNo?: string | null;

  @IsOptional()
  @Matches(DATE_PATTERN)
  invoiceDate?: string | null;

  @IsOptional()
  @Matches(DATE_PATTERN)
  receivedOn?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  transportPermitNo?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  invoicePhotoUrl?: string | null;

  @IsOptional()
  invoiceValue?: DecimalInput | null;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => GrnLineDto)
  lines?: GrnLineDto[];
}

export class GrnCreateDto extends GrnBaseDto {
  @IsOptional()
  @IsString()
  poId?: string;
}

export class GrnUpdateDto extends GrnBaseDto {}
