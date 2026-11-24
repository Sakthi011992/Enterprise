import { ApiProperty } from '@nestjs/swagger';

export class AuthUserEntity {
  @ApiProperty() id: string;
  @ApiProperty() username: string;
  @ApiProperty({ nullable: true }) email: string | null;
  @ApiProperty() role: string;
  @ApiProperty({ type: [String] }) features: string[];
}

export class LoginResponseEntity {
  @ApiProperty() accessToken: string;
  @ApiProperty() refreshToken: string;
  @ApiProperty({ type: AuthUserEntity }) user: AuthUserEntity;
}

export class RefreshResponseEntity {
  @ApiProperty() accessToken: string;
}

export class LogoutResponseEntity {
  @ApiProperty() success: boolean;
}
