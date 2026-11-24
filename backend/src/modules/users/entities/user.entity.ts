import { ApiProperty } from '@nestjs/swagger';

export class UserRoleEntity {
  @ApiProperty() name: string;
}

export class UserFeatureGrantEntity {
  @ApiProperty() feature: string;
}

export class UserEntity {
  @ApiProperty() id: string;
  @ApiProperty() username: string;
  @ApiProperty() isActive: boolean;
  @ApiProperty() createdAt: Date;
  @ApiProperty() updatedAt: Date;
  @ApiProperty({ type: UserRoleEntity }) role: UserRoleEntity;
  @ApiProperty({ type: [UserFeatureGrantEntity] }) featureGrants: UserFeatureGrantEntity[];
}

export class UsersListEntity {
  @ApiProperty({ type: [UserEntity] }) data: UserEntity[];
  @ApiProperty() meta: Record<string, number>;
}
