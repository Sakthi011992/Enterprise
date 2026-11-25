import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, Matches, MaxLength, MinLength } from 'class-validator';

export class SelectOutletDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  selectionToken: string;

  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  outletId: string;
}

export class SwitchOutletDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  outletId: string;
}

export class ForgotPasswordDto {
  @ApiProperty({ description: 'Username or email' })
  @IsString()
  @MinLength(3)
  @MaxLength(120)
  usernameOrEmail: string;
}

export class ResetPasswordDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  token: string;

  @ApiProperty({ minLength: 8, description: 'At least one letter and one digit' })
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  @Matches(/^(?=.*[A-Za-z])(?=.*\d).+$/, { message: 'newPassword must contain a letter and a digit' })
  newPassword: string;
}

export class PinLoginDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  userId: string;

  @ApiProperty({ example: '2580' })
  @IsString()
  @Matches(/^\d{4}$/, { message: 'pin must be 4 digits' })
  pin: string;
}
