import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsBoolean,
  IsEmail,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
  ValidateNested,
} from 'class-validator';

export class CreateUserDto {
  @ApiProperty()
  @IsString()
  @MinLength(3)
  username: string;

  @ApiPropertyOptional({ description: 'Optional: PIN-only staff may have no email' })
  @IsOptional()
  @IsEmail()
  email?: string;

  @ApiProperty()
  @IsString()
  @MinLength(6)
  password: string;

  @ApiPropertyOptional({
    enum: ['ADMIN', 'USER', 'KIOSK'],
    default: 'USER',
    description: 'Legacy role. Also picks the starting persona: ADMIN gives admin, USER gives cashier, KIOSK gives kiosk',
  })
  @IsOptional()
  @IsIn(['ADMIN', 'USER', 'KIOSK'])
  roleName?: 'ADMIN' | 'USER' | 'KIOSK';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  displayName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(20)
  phone?: string;
}

export class UpdateUserDto extends PartialType(CreateUserDto) {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class ResetPasswordDto {
  @ApiProperty()
  @IsString()
  @MinLength(6)
  newPassword: string;
}

export class SetPinDto {
  @ApiProperty({ example: '2580' })
  @IsString()
  @Matches(/^\d{4}$/, { message: 'pin must be 4 digits' })
  pin: string;
}

export class UserOutletItemDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  outletId: string;

  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  personaId: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  isDefault?: boolean = false;
}

export class SetUserOutletsDto {
  @ApiProperty({ type: [UserOutletItemDto] })
  @ValidateNested({ each: true })
  @Type(() => UserOutletItemDto)
  @ArrayMaxSize(50)
  items: UserOutletItemDto[];
}
