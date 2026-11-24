import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcrypt';
import { AuthRepository } from './auth.repository';
import { JwtPayload } from './jwt.strategy';

@Injectable()
export class AuthService {
  constructor(
    private repo: AuthRepository,
    private jwt: JwtService,
    private config: ConfigService,
  ) {}

  private async userFeatures(userId: string): Promise<string[]> {
    const grants = await this.repo.getFeatureGrants(userId);
    return grants.map((g) => g.feature);
  }

  async validateUser(username: string, password: string) {
    const user = await this.repo.findUserByUsername(username);
    if (!user || !user.isActive) throw new UnauthorizedException('Invalid credentials');
    const ok = user.passwordHash ? await bcrypt.compare(password, user.passwordHash) : false;
    if (!ok) throw new UnauthorizedException('Invalid credentials');
    return user;
  }

  private async issueTokens(user: { id: string; username: string; tokenVersion: number; role: { name: string } }) {
    const payload: JwtPayload = {
      sub: user.id,
      username: user.username,
      role: user.role.name as 'ADMIN' | 'USER',
      tokenVersion: user.tokenVersion,
    };
    const accessToken = await this.jwt.signAsync(payload, {
      secret: this.config.get('JWT_ACCESS_SECRET'),
      expiresIn: this.config.get('JWT_ACCESS_EXPIRES', '15m'),
    });
    const refreshToken = await this.jwt.signAsync(payload, {
      secret: this.config.get('JWT_REFRESH_SECRET'),
      expiresIn: this.config.get('JWT_REFRESH_EXPIRES', '7d'),
    });
    return { accessToken, refreshToken };
  }

  async login(username: string, password: string) {
    const user = await this.validateUser(username, password);
    const tokens = await this.issueTokens(user);
    const features = await this.userFeatures(user.id);
    return {
      ...tokens,
      user: { id: user.id, username: user.username, email: user.email, role: user.role.name, features },
    };
  }

  async refresh(refreshToken: string) {
    let payload: JwtPayload;
    try {
      payload = await this.jwt.verifyAsync(refreshToken, {
        secret: this.config.get('JWT_REFRESH_SECRET'),
      });
    } catch {
      throw new UnauthorizedException('Invalid refresh token');
    }
    const user = await this.repo.findActiveUserById(payload.sub);
    if (!user || user.tokenVersion !== payload.tokenVersion) {
      throw new UnauthorizedException('Refresh token revoked');
    }
    const accessToken = await this.jwt.signAsync(
      { sub: user.id, username: user.username, role: user.role.name, tokenVersion: user.tokenVersion },
      { secret: this.config.get('JWT_ACCESS_SECRET'), expiresIn: this.config.get('JWT_ACCESS_EXPIRES', '15m') },
    );
    return { accessToken };
  }

  async logout(userId: string) {
    await this.repo.revokeTokens(userId);
    return { success: true };
  }

  async me(userId: string) {
    const user = await this.repo.findUserById(userId);
    if (!user) throw new UnauthorizedException();
    const features = await this.userFeatures(user.id);
    return { id: user.id, username: user.username, email: user.email, role: user.role.name, features };
  }
}
