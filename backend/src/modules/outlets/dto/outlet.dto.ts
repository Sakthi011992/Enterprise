import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';

export class CreateOutletDto {
  @ApiProperty({ example: 'Main outlet' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiProperty({ example: 'MAIN', description: 'Letters, digits, dash or underscore. Stored in upper case' })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim().toUpperCase() : value))
  @IsString()
  @Matches(/^[A-Z0-9_-]{2,12}$/, { message: 'code must be 2-12 letters, digits, - or _' })
  code: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  address?: string;

  @ApiPropertyOptional({ example: 'Asia/Kolkata' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  timezone?: string;
}

export class UpdateOutletDto extends PartialType(CreateOutletDto) {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
