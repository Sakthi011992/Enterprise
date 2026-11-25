import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

export const PRINTER_CONNECTIONS = ['LAN', 'USB', 'BLUETOOTH'] as const;
export const PAPER_WIDTHS = [58, 80] as const;

export class CreatePrinterDto {
  @ApiProperty({ example: 'Main bar BOT' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiPropertyOptional({ enum: PRINTER_CONNECTIONS, default: 'LAN' })
  @IsOptional()
  @IsIn([...PRINTER_CONNECTIONS])
  connection?: (typeof PRINTER_CONNECTIONS)[number];

  @ApiPropertyOptional({ example: '192.168.1.31', description: 'Required for LAN printers' })
  @IsOptional()
  @IsString()
  @MaxLength(255)
  host?: string | null;

  @ApiPropertyOptional({ default: 9100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(65535)
  port?: number;

  @ApiPropertyOptional({ enum: PAPER_WIDTHS, default: 80 })
  @IsOptional()
  @Type(() => Number)
  @IsIn([...PAPER_WIDTHS])
  paperWidth?: (typeof PAPER_WIDTHS)[number];

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(5)
  copies?: number;

  @ApiPropertyOptional({ enum: ['en', 'ta'], default: 'en' })
  @IsOptional()
  @IsIn(['en', 'ta'])
  language?: 'en' | 'ta';

  @ApiPropertyOptional({ default: false, description: 'Bills, X/Z reports and the cash drawer go to a receipt printer' })
  @IsOptional()
  @IsBoolean()
  isReceipt?: boolean;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class UpdatePrinterDto extends PartialType(CreatePrinterDto) {}

export class StationRouteItemDto {
  @ApiProperty({ example: 'BAR', description: 'Matches Category.station' })
  @IsString()
  @MinLength(1)
  @MaxLength(40)
  station: string;

  @ApiPropertyOptional({ type: String, nullable: true })
  @IsOptional()
  @IsString()
  printerId?: string | null;

  @ApiPropertyOptional({ type: String, nullable: true })
  @IsOptional()
  @IsString()
  fallbackPrinterId?: string | null;
}

export class UpdateStationRoutesDto {
  @ApiProperty({ type: [StationRouteItemDto] })
  @IsArray()
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => StationRouteItemDto)
  items: StationRouteItemDto[];
}

export class PrintJobResultDto {
  @ApiProperty()
  @IsBoolean()
  ok: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  error?: string;

  @ApiPropertyOptional({ enum: ['READY', 'PAPER_LOW', 'OFFLINE'] })
  @IsOptional()
  @IsIn(['READY', 'PAPER_LOW', 'OFFLINE'])
  printerStatus?: 'READY' | 'PAPER_LOW' | 'OFFLINE';
}
