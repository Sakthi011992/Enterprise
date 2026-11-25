import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsOptional, IsString, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';

export const TICKET_KINDS = ['KOT', 'BOT'] as const;

export class CreateCategoryDto {
  @ApiProperty({ example: 'Spirits' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @ApiPropertyOptional({ example: 'BAR', default: 'KITCHEN', description: 'Routing key matched by station routes' })
  @IsOptional()
  @IsString()
  @Matches(/^[A-Z][A-Z0-9_]{0,39}$/, { message: 'station must be upper case letters, digits or underscore' })
  station?: string;

  @ApiPropertyOptional({ enum: TICKET_KINDS, default: 'KOT', description: 'BOT for drinks' })
  @IsOptional()
  @IsIn([...TICKET_KINDS])
  ticketKind?: (typeof TICKET_KINDS)[number];

  @ApiPropertyOptional({ type: String, nullable: true })
  @IsOptional()
  @IsString()
  taxClassId?: string | null;

  @ApiPropertyOptional({ example: '#E0A526', type: String, nullable: true })
  @IsOptional()
  @Matches(/^#[0-9a-fA-F]{6}$/, { message: 'color must be a hex colour such as #E0A526' })
  color?: string | null;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class UpdateCategoryDto extends PartialType(CreateCategoryDto) {}
