import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsIn,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { ACCESS_LEVELS } from '../../../common/permissions/catalog';

export class CreatePersonaDto {
  @ApiProperty({ example: 'Shift lead' })
  @IsString()
  @MinLength(2)
  @MaxLength(60)
  name: string;

  @ApiPropertyOptional({ description: 'Copy the permission matrix from this persona' })
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  copyFromId?: string;
}

export class UpdatePersonaDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(60)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  description?: string;

  @ApiPropertyOptional({ example: '/pos' })
  @IsOptional()
  @IsString()
  @Matches(/^\//, { message: 'homeRoute must start with /' })
  homeRoute?: string;

  @ApiPropertyOptional({ enum: ['PASSWORD', 'PIN'] })
  @IsOptional()
  @IsIn(['PASSWORD', 'PIN'])
  loginMethod?: 'PASSWORD' | 'PIN';
}

export class PermissionItemDto {
  @ApiProperty({ example: 'sales.discount.give' })
  @IsString()
  key: string;

  @ApiProperty({ enum: [...ACCESS_LEVELS] })
  @IsIn([...ACCESS_LEVELS])
  level: (typeof ACCESS_LEVELS)[number];

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsNumber()
  @Min(0)
  limit?: number | null;
}

export class SetPermissionsDto {
  @ApiProperty({ type: [PermissionItemDto], description: 'Full matrix. Keys left out become NONE' })
  @ValidateNested({ each: true })
  @Type(() => PermissionItemDto)
  @ArrayMaxSize(200)
  items: PermissionItemDto[];
}
