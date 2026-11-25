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
import { PaymentMethod } from '@prisma/client';

/** Legacy POST /payments body: one payment against an order. Still accepted. */
export class CreatePaymentDto {
  @ApiProperty()
  @IsUUID()
  orderId: string;

  @ApiProperty({ example: 210 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  amount: number;

  @ApiProperty({ enum: PaymentMethod })
  @IsEnum(PaymentMethod)
  paymentMethod: PaymentMethod;
}

export class PaymentLineDto {
  @ApiProperty({ enum: PaymentMethod })
  @IsEnum(PaymentMethod)
  method: PaymentMethod;

  @ApiProperty({ example: 300 })
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  amount: number;

  @ApiPropertyOptional({ description: 'Cash handed over. Missing = exact amount' })
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  tendered?: number;

  @ApiPropertyOptional({ description: 'UPI or card reference' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  reference?: string;

  @ApiPropertyOptional({ minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  seat?: number;
}

export class PayOrderDto {
  @ApiProperty({ type: [PaymentLineDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => PaymentLineDto)
  payments: PaymentLineDto[];

  @ApiPropertyOptional({ description: 'Tip; attached to the cash line when there is one, otherwise the first line' })
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  tipAmount?: number;

  @ApiPropertyOptional({ description: 'The seat is paid in full by these lines' })
  @IsOptional()
  @IsBoolean()
  completeSeat?: boolean;
}

export class RefundDto {
  @ApiProperty()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  amount: number;

  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  reason: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  paymentId?: string;

  @ApiPropertyOptional({ description: 'Approved REFUND approval, needed unless the caller holds APPROVE on sales.void' })
  @IsOptional()
  @IsUUID()
  approvalId?: string;
}

export class SplitQueryDto {
  @ApiProperty({ enum: ['EQUAL', 'SEAT', 'ITEMS'] })
  @IsIn(['EQUAL', 'SEAT', 'ITEMS'])
  mode: 'EQUAL' | 'SEAT' | 'ITEMS';

  @ApiPropertyOptional({ minimum: 2, maximum: 10 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(2)
  @Max(10)
  parts?: number;

  @ApiPropertyOptional({ example: 'itemA:1,itemB:2,itemB:3' })
  @IsOptional()
  @IsString()
  assign?: string;
}
