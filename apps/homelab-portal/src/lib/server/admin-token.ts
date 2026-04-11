import type { KeycloakClient } from './keycloak';

const EXPIRY_BUFFER_SECONDS = 30;

export class AdminTokenCache {
  private token: string | null = null;
  private expiresAt: number = 0;

  constructor(private kc: KeycloakClient) {}

  async get(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.token && now < this.expiresAt - EXPIRY_BUFFER_SECONDS) {
      return this.token;
    }

    const tokens = await this.kc.clientCredentialsToken();
    this.token = tokens.access_token;
    this.expiresAt = now + tokens.expires_in;
    return this.token;
  }
}
