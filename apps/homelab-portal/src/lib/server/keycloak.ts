export interface KeycloakConfig {
  url: string;
  publicUrl: string;
  realm: string;
  clientId: string;
  clientSecret: string;
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: string;
  id_token?: string;
}

export interface UserInfo {
  sub: string;
  email: string;
  email_verified?: boolean;
  given_name?: string;
  family_name?: string;
  name?: string;
  preferred_username?: string;
}

export interface CreateUserRequest {
  email: string;
  firstName: string;
  lastName: string;
  password: string;
}

export class KeycloakClient {
  constructor(private config: KeycloakConfig) {}

  private tokenUrl(): string {
    return `${this.config.url}/realms/${this.config.realm}/protocol/openid-connect/token`;
  }

  private userinfoUrl(): string {
    return `${this.config.url}/realms/${this.config.realm}/protocol/openid-connect/userinfo`;
  }

  private adminUrl(path: string): string {
    return `${this.config.url}/admin/realms/${this.config.realm}${path}`;
  }

  private accountUrl(): string {
    return `${this.config.url}/realms/${this.config.realm}/account`;
  }

  async passwordLogin(username: string, password: string): Promise<TokenResponse> {
    const body = new URLSearchParams({
      grant_type: 'password',
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret,
      username,
      password,
      scope: 'openid email profile'
    });

    const res = await fetch(this.tokenUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error_description || err.error || `HTTP ${res.status}`);
    }

    return res.json();
  }

  async refreshToken(refreshToken: string): Promise<TokenResponse> {
    const body = new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret,
      refresh_token: refreshToken
    });

    const res = await fetch(this.tokenUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error_description || err.error || `HTTP ${res.status}`);
    }

    return res.json();
  }

  async clientCredentialsToken(): Promise<TokenResponse> {
    const body = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret
    });

    const res = await fetch(this.tokenUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error_description || err.error || `HTTP ${res.status}`);
    }

    return res.json();
  }

  async userinfo(accessToken: string): Promise<UserInfo> {
    const res = await fetch(this.userinfoUrl(), {
      headers: { Authorization: `Bearer ${accessToken}` }
    });

    if (!res.ok) {
      throw new Error(`userinfo failed: HTTP ${res.status}`);
    }

    return res.json();
  }

  async logoutUrl(idToken: string, postLogoutRedirectUri: string): Promise<string> {
    const params = new URLSearchParams({
      id_token_hint: idToken,
      post_logout_redirect_uri: postLogoutRedirectUri,
      client_id: this.config.clientId
    });
    return `${this.config.publicUrl}/realms/${this.config.realm}/protocol/openid-connect/logout?${params}`;
  }

  async createUser(adminToken: string, user: CreateUserRequest): Promise<string> {
    const res = await fetch(this.adminUrl('/users'), {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${adminToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        username: user.email,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        enabled: true,
        emailVerified: false,
        credentials: [{ type: 'password', value: user.password, temporary: false }]
      })
    });

    if (res.status === 409) {
      throw new Error('An account with this email already exists');
    }
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`createUser failed: HTTP ${res.status} ${err}`);
    }

    const location = res.headers.get('Location');
    if (!location) throw new Error('createUser: no Location header');
    const id = location.split('/').pop();
    if (!id) throw new Error('createUser: failed to parse user id');
    return id;
  }

  async sendVerifyEmail(adminToken: string, userId: string): Promise<void> {
    const res = await fetch(this.adminUrl(`/users/${userId}/send-verify-email`), {
      method: 'PUT',
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    if (!res.ok) {
      throw new Error(`sendVerifyEmail failed: HTTP ${res.status}`);
    }
  }

  async findUserByEmail(adminToken: string, email: string): Promise<{ id: string } | null> {
    const res = await fetch(this.adminUrl(`/users?email=${encodeURIComponent(email)}&exact=true`), {
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    if (!res.ok) {
      throw new Error(`findUserByEmail failed: HTTP ${res.status}`);
    }
    const users = await res.json();
    return users.length > 0 ? { id: users[0].id } : null;
  }

  async executeActionsEmail(adminToken: string, userId: string, actions: string[]): Promise<void> {
    const res = await fetch(this.adminUrl(`/users/${userId}/execute-actions-email`), {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${adminToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(actions)
    });
    if (!res.ok) {
      throw new Error(`executeActionsEmail failed: HTTP ${res.status}`);
    }
  }

  async updateAccount(
    accessToken: string,
    updates: { email?: string; firstName?: string; lastName?: string }
  ): Promise<void> {
    const res = await fetch(this.accountUrl(), {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        Accept: 'application/json'
      },
      body: JSON.stringify(updates)
    });

    if (!res.ok) {
      const err = await res.text();
      throw new Error(`updateAccount failed: HTTP ${res.status} ${err}`);
    }
  }
}
