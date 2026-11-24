import { IsBoolean, IsInt, IsOptional, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class SetOrderingEnabledDto {
  @ApiProperty() @IsBoolean() enabled: boolean;
}

export class CreateFeaturedItemDto {
  @ApiProperty() @IsString() productId: string;
  @IsOptional() @IsString() label?: string;
  @IsOptional() @IsInt() sortOrder?: number;
  @IsOptional() @IsString() storeId?: string;
  @IsOptional() @IsString() startsAt?: string;
  @IsOptional() @IsString() endsAt?: string;
}

export class UpdateFeaturedItemDto {
  @IsOptional() @IsString() label?: string;
  @IsOptional() @IsInt() sortOrder?: number;
  @IsOptional() @IsBoolean() isActive?: boolean;
  @IsOptional() @IsString() startsAt?: string;
  @IsOptional() @IsString() endsAt?: string;
}
