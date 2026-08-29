import { IsOptional, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class GenerateInvoiceDto {
  @ApiProperty() @IsString() orderId: string;
  @IsOptional() @IsString() countryCode?: string;
}

export class AuditQueryDto {
  @IsOptional() @IsString() from?: string;
  @IsOptional() @IsString() to?: string;
  @IsOptional() @IsString() countryCode?: string;
  @IsOptional() @IsString() status?: string;
  @IsOptional() @IsString() invoiceNumber?: string;
  page?: number = 1;
  limit?: number = 20;
}
