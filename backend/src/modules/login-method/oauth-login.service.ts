import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { LoginMethod, User } from '@prisma/client';
import { OAuth2Client } from 'google-auth-library';
import { AuthService } from '../auth/auth.service';
import { OAuthRepository } from './oauth.repository';

@Injectable()
export class OAuthLoginService {
  private googleClient: OAuth2Client;

  constructor(
    private repo: OAuthRepository,
    private auth: AuthService,
    private config: ConfigService,
  ) {
    this.googleClient = new OAuth2Client(config.get('GOOGLE_OAUTH_CLIENT_ID'));
  }

  /** Verifies the Google ID token and returns the same session payload as password login (PLAN 4.3). */
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

    const user = await this.findOrCreateUser(LoginMethod.GOOGLE, payload.sub, payload.email);
    return this.auth.completeLogin(user.id, user.tenantId);
  }

  private async findOrCreateUser(provider: LoginMethod, providerUserId: string, email?: string) {
    const account = await this.repo.findAccountUser(provider, providerUserId);
    let user: User | null = account?.user ?? null;

    if (!user) {
      // Auto-link by verified email, otherwise create a user in the default tenant.
      user = email ? await this.repo.findUserByEmail(email) : null;

      if (!user) {
        const tenant = await this.repo.findDefaultTenant();
        const role = await this.repo.findRoleIdByName('USER');
        if (!tenant || !role) throw new UnauthorizedException('Login is not set up for this tenant');
        const username = email?.split('@')[0] ?? `oauth_${providerUserId.slice(0, 8)}`;
        const created = await this.repo.createUser({ tenantId: tenant.id, username, email, roleId: role.id });
        user = created;
      }

      if (!user) throw new UnauthorizedException('Login is not set up for this tenant');
      await this.repo.createAccount({ userId: user.id, provider, providerUserId, email });
    }

    if (!user || !user.isActive || user.deletedAt) throw new UnauthorizedException('Account is inactive');
    return user;
  }
}
