import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { LoginMethod } from '@prisma/client';
import { OAuth2Client } from 'google-auth-library';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class OAuthLoginService {
  private googleClient: OAuth2Client;

  constructor(
    private prisma: PrismaService,
    private jwt: JwtService,
    private config: ConfigService,
  ) {
    this.googleClient = new OAuth2Client(config.get('GOOGLE_OAUTH_CLIENT_ID'));
  }

  async loginWithGoogleToken(idToken: string) {
    const clientId = this.config.get<string>('GOOGLE_OAUTH_CLIENT_ID');
    let ticket: any;
    try {
      ticket = await this.googleClient.verifyIdToken({ idToken, audience: clientId });
    } catch {
      throw new UnauthorizedException('Invalid Google ID token');
    }
    const payload = ticket.getPayload();
    if (!payload?.sub) throw new UnauthorizedException('No subject in Google token');

    return this.findOrCreateUser(LoginMethod.GOOGLE, payload.sub, payload.email);
  }

  private async findOrCreateUser(provider: LoginMethod, providerUserId: string, email?: string) {
    let oauthAccount = await this.prisma.oAuthAccount.findUnique({
      where: { provider_providerUserId: { provider, providerUserId } },
      include: { user: { include: { role: true } } },
    });

    if (!oauthAccount) {
      // auto-link by verified email
      let user = email
        ? await this.prisma.user.findFirst({ where: { email, deletedAt: null }, include: { role: true } })
        : null;

      if (!user) {
        const role = await this.prisma.role.findFirst({ where: { name: 'USER' } });
        const username = email?.split('@')[0] ?? `oauth_${providerUserId.slice(0, 8)}`;
        user = await this.prisma.user.create({
          data: {
            username,
            email,
            roleId: role!.id,
          },
          include: { role: true },
        });
      }

      oauthAccount = await this.prisma.oAuthAccount.create({
        data: { userId: user.id, provider, providerUserId, email },
        include: { user: { include: { role: true } } },
      });
    }

    const user = oauthAccount.user;
    if (!user.isActive) throw new UnauthorizedException('Account is inactive');

    const grants = await this.prisma.userFeatureGrant.findMany({ where: { userId: user.id } });
    const features = grants.map((g) => g.feature);

    const accessToken = await this.jwt.signAsync(
      { sub: user.id, username: user.username, role: user.role.name, tokenVersion: user.tokenVersion },
      { secret: this.config.get('JWT_ACCESS_SECRET'), expiresIn: this.config.get('JWT_ACCESS_EXPIRES', '15m') },
    );
    const refreshToken = await this.jwt.signAsync(
      { sub: user.id, username: user.username, role: user.role.name, tokenVersion: user.tokenVersion },
      { secret: this.config.get('JWT_REFRESH_SECRET'), expiresIn: this.config.get('JWT_REFRESH_EXPIRES', '7d') },
    );

    return {
      accessToken,
      refreshToken,
      user: { id: user.id, username: user.username, email: user.email, role: user.role.name, features },
    };
  }
}
