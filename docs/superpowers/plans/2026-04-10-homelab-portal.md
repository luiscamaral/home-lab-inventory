# Homelab Portal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a SvelteKit login portal at `login.cf.lcamaral.com` with login, registration, password reset, and profile editing, using Keycloak as the OIDC backend.

**Architecture:** SvelteKit SSR app with server-side OAuth2 (ROPC for login, Admin API for registration, Account API for profile edits). HTTP-only signed+encrypted cookies for sessions. Deployed as Portainer stack via Terraform.

**Tech Stack:** Svelte 5, SvelteKit, TypeScript, pnpm, Tailwind CSS v4, Flowbite, Vitest, Playwright, Node.js 22 Alpine, Docker multi-stage build

**Spec:** `docs/superpowers/specs/2026-04-10-homelab-portal-design.md`

---

### Task 1: Keycloak setup — create homelab-portal OIDC client

**Files:** None (Keycloak REST API operation)

- [ ] **Step 1: Get admin token and store in shell**

```bash
export VAULT_ADDR="http://vault.d.lcamaral.com"
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
KC_ADMIN_PW=$(vault kv get -field=admin_password secret/homelab/keycloak)
KC_TOKEN=$(/usr/bin/curl -s https://auth.cf.lcamaral.com/realms/master/protocol/openid-connect/token \
  -d "client_id=admin-cli" -d "username=admin" \
  --data-urlencode "password=${KC_ADMIN_PW}" \
  -d "grant_type=password" | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
echo "Token: ${KC_TOKEN:0:20}..."
```

- [ ] **Step 2: Create homelab-portal OIDC client**

```bash
CLIENT_SECRET=$(openssl rand -hex 32)
/usr/bin/curl -s -o /dev/null -w "%{http_code}" \
  "https://auth.cf.lcamaral.com/admin/realms/homelab/clients" \
  -H "Authorization: Bearer ${KC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"clientId\": \"homelab-portal\",
    \"name\": \"Homelab Portal\",
    \"enabled\": true,
    \"protocol\": \"openid-connect\",
    \"publicClient\": false,
    \"secret\": \"${CLIENT_SECRET}\",
    \"standardFlowEnabled\": true,
    \"directAccessGrantsEnabled\": true,
    \"serviceAccountsEnabled\": true,
    \"redirectUris\": [\"https://login.cf.lcamaral.com/auth/callback\"],
    \"webOrigins\": [\"https://login.cf.lcamaral.com\"],
    \"attributes\": {\"pkce.code.challenge.method\": \"\"}
  }"
echo " (create client)"
echo "SECRET: ${CLIENT_SECRET}"
```

Expected: `201 (create client)`

- [ ] **Step 3: Assign realm-management roles to service account**

```bash
CLIENT_UUID=$(/usr/bin/curl -s "https://auth.cf.lcamaral.com/admin/realms/homelab/clients?clientId=homelab-portal" \
  -H "Authorization: Bearer ${KC_TOKEN}" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")

SA_USER_ID=$(/usr/bin/curl -s "https://auth.cf.lcamaral.com/admin/realms/homelab/clients/${CLIENT_UUID}/service-account-user" \
  -H "Authorization: Bearer ${KC_TOKEN}" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

REALM_MGMT_ID=$(/usr/bin/curl -s "https://auth.cf.lcamaral.com/admin/realms/homelab/clients?clientId=realm-management" \
  -H "Authorization: Bearer ${KC_TOKEN}" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")

for ROLE in manage-users view-users query-users; do
  ROLE_JSON=$(/usr/bin/curl -s "https://auth.cf.lcamaral.com/admin/realms/homelab/clients/${REALM_MGMT_ID}/roles/${ROLE}" \
    -H "Authorization: Bearer ${KC_TOKEN}")
  /usr/bin/curl -s -o /dev/null -w "%{http_code} " \
    "https://auth.cf.lcamaral.com/admin/realms/homelab/users/${SA_USER_ID}/role-mappings/clients/${REALM_MGMT_ID}" \
    -H "Authorization: Bearer ${KC_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "[${ROLE_JSON}]"
  echo "(${ROLE})"
done
```

Expected: `204 (manage-users) 204 (view-users) 204 (query-users)`

- [ ] **Step 4: Store client secret in Vault**

```bash
vault kv patch secret/homelab/keycloak/clients homelab_portal_secret="${CLIENT_SECRET}"
```

Expected: `secret/data/homelab/keycloak/clients` path with version 2.

- [ ] **Step 5: Generate and store portal session secrets in Vault**

```bash
vault kv put secret/homelab/portal \
  session_secret="$(openssl rand -hex 32)" \
  session_encryption_key="$(openssl rand -hex 32)"
```

Expected: `secret/data/homelab/portal` path created.

---

### Task 2: Scaffold SvelteKit project

**Files:**
- Create: `apps/homelab-portal/package.json`
- Create: `apps/homelab-portal/pnpm-lock.yaml`
- Create: `apps/homelab-portal/svelte.config.js`
- Create: `apps/homelab-portal/vite.config.ts`
- Create: `apps/homelab-portal/tsconfig.json`
- Create: `apps/homelab-portal/tailwind.config.ts`
- Create: `apps/homelab-portal/src/app.html`
- Create: `apps/homelab-portal/src/app.css`
- Create: `apps/homelab-portal/src/app.d.ts`
- Create: `apps/homelab-portal/.gitignore`

- [ ] **Step 1: Create directory and scaffold SvelteKit**

```bash
mkdir -p apps/homelab-portal
cd apps/homelab-portal
pnpm dlx sv@latest create . --template minimal --types ts --no-add-ons --install pnpm
```

When prompted, overwrite any existing files. Expected: `src/`, `package.json`, `svelte.config.js` created.

- [ ] **Step 2: Install required dependencies**

```bash
cd apps/homelab-portal
pnpm add -D tailwindcss@latest @tailwindcss/vite@latest flowbite flowbite-svelte \
  @types/node vitest @playwright/test @sveltejs/adapter-node
pnpm add jose
```

Expected: `package.json` has these in deps/devDeps.

- [ ] **Step 3: Replace `svelte.config.js` with Node adapter**

```javascript
import adapter from '@sveltejs/adapter-node';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({ out: 'build' })
  }
};

export default config;
```

- [ ] **Step 4: Configure Vite with Tailwind**

Write `vite.config.ts`:

```typescript
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [tailwindcss(), sveltekit()],
  server: {
    port: 3000,
    strictPort: true
  }
});
```

- [ ] **Step 5: Write `src/app.css` with Tailwind + Flowbite imports**

```css
@import "tailwindcss";
@import "flowbite/src/themes/default";

@plugin "flowbite/plugin";

@source "../node_modules/flowbite";

@custom-variant dark (&:where(.dark, .dark *));
```

- [ ] **Step 6: Update `src/app.html` to load app.css**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <link rel="icon" href="%sveltekit.assets%/favicon.png" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Homelab Portal</title>
    %sveltekit.head%
  </head>
  <body data-sveltekit-preload-data="hover" class="bg-gray-50 dark:bg-gray-900">
    <div style="display: contents">%sveltekit.body%</div>
  </body>
</html>
```

- [ ] **Step 7: Update `src/app.d.ts` with locals type**

```typescript
declare global {
  namespace App {
    interface Locals {
      user?: {
        sub: string;
        email: string;
        name: string;
        firstName: string;
        lastName: string;
      };
    }
  }
}

export {};
```

- [ ] **Step 8: Add `dev:test` script and import app.css in root layout**

Edit `apps/homelab-portal/package.json` — ensure scripts include:

```json
{
  "scripts": {
    "dev": "vite dev",
    "build": "vite build",
    "preview": "vite preview",
    "check": "svelte-kit sync && svelte-check --tsconfig ./tsconfig.json",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:e2e": "playwright test"
  }
}
```

Create `apps/homelab-portal/src/routes/+layout.svelte`:

```svelte
<script lang="ts">
  import '../app.css';
  let { children } = $props();
</script>

{@render children()}
```

- [ ] **Step 9: Verify build works**

```bash
cd apps/homelab-portal
pnpm install
pnpm build
```

Expected: `build/` directory with `index.js` and other assets. No errors.

- [ ] **Step 10: Commit**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add apps/homelab-portal/
git commit -m "feat(portal): scaffold SvelteKit + Tailwind + Flowbite project"
```

---

### Task 3: Session module (encode/decode signed+encrypted cookies)

**Files:**
- Create: `apps/homelab-portal/src/lib/server/session.ts`
- Create: `apps/homelab-portal/src/lib/server/session.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/homelab-portal/src/lib/server/session.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { encodeSession, decodeSession, type SessionData } from './session';

const SECRET = 'a'.repeat(64);
const ENC_KEY = 'b'.repeat(64);

describe('session', () => {
  it('encodes and decodes a session roundtrip', async () => {
    const data: SessionData = {
      sub: 'user-123',
      email: 'test@example.com',
      name: 'Test User',
      firstName: 'Test',
      lastName: 'User',
      accessToken: 'abc.def.ghi',
      refreshToken: 'refresh-token-value',
      accessTokenExpiresAt: Math.floor(Date.now() / 1000) + 3600
    };

    const cookie = await encodeSession(data, SECRET, ENC_KEY);
    expect(cookie).toBeTypeOf('string');
    expect(cookie.length).toBeGreaterThan(100);

    const decoded = await decodeSession(cookie, SECRET, ENC_KEY);
    expect(decoded).toEqual(data);
  });

  it('rejects tampered cookies', async () => {
    const data: SessionData = {
      sub: 'user-123',
      email: 'test@example.com',
      name: 'Test User',
      firstName: 'Test',
      lastName: 'User',
      accessToken: 'token',
      refreshToken: 'refresh',
      accessTokenExpiresAt: 0
    };
    const cookie = await encodeSession(data, SECRET, ENC_KEY);
    const tampered = cookie.slice(0, -5) + 'xxxxx';
    await expect(decodeSession(tampered, SECRET, ENC_KEY)).rejects.toThrow();
  });

  it('rejects cookies signed with different secret', async () => {
    const data: SessionData = {
      sub: 'user-123',
      email: 'test@example.com',
      name: 'Test User',
      firstName: 'Test',
      lastName: 'User',
      accessToken: 'token',
      refreshToken: 'refresh',
      accessTokenExpiresAt: 0
    };
    const cookie = await encodeSession(data, SECRET, ENC_KEY);
    await expect(decodeSession(cookie, 'c'.repeat(64), ENC_KEY)).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd apps/homelab-portal
pnpm test src/lib/server/session.test.ts
```

Expected: FAIL — `Cannot find module './session'`

- [ ] **Step 3: Implement session module**

Create `apps/homelab-portal/src/lib/server/session.ts`:

```typescript
import { EncryptJWT, jwtDecrypt, errors } from 'jose';

export interface SessionData {
  sub: string;
  email: string;
  name: string;
  firstName: string;
  lastName: string;
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: number;
}

const MAX_AGE_SECONDS = 60 * 60 * 24 * 7; // 7 days

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

export async function encodeSession(
  data: SessionData,
  signingSecret: string,
  encryptionKey: string
): Promise<string> {
  if (encryptionKey.length !== 64) {
    throw new Error('encryptionKey must be 64 hex chars (32 bytes)');
  }
  if (signingSecret.length < 32) {
    throw new Error('signingSecret must be at least 32 chars');
  }

  const key = hexToBytes(encryptionKey);

  const jwt = await new EncryptJWT({
    data,
    sig: signingSecret.substring(0, 16)
  })
    .setProtectedHeader({ alg: 'dir', enc: 'A256GCM' })
    .setIssuedAt()
    .setExpirationTime(`${MAX_AGE_SECONDS}s`)
    .encrypt(key);

  return jwt;
}

export async function decodeSession(
  cookie: string,
  signingSecret: string,
  encryptionKey: string
): Promise<SessionData> {
  const key = hexToBytes(encryptionKey);

  const { payload } = await jwtDecrypt(cookie, key);

  if (payload.sig !== signingSecret.substring(0, 16)) {
    throw new Error('Session signature mismatch');
  }

  return payload.data as SessionData;
}

export const SESSION_COOKIE_NAME = 'hl_session';

export const SESSION_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: true,
  sameSite: 'lax' as const,
  path: '/',
  maxAge: MAX_AGE_SECONDS
};
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pnpm test src/lib/server/session.test.ts
```

Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add apps/homelab-portal/src/lib/server/session.ts apps/homelab-portal/src/lib/server/session.test.ts
git commit -m "feat(portal): session encode/decode with encrypted JWT cookies"
```

---

### Task 4: Keycloak client module

**Files:**
- Create: `apps/homelab-portal/src/lib/server/keycloak.ts`
- Create: `apps/homelab-portal/src/lib/server/keycloak.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `apps/homelab-portal/src/lib/server/keycloak.test.ts`:

```typescript
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { KeycloakClient } from './keycloak';

const fetchMock = vi.fn();
globalThis.fetch = fetchMock as any;

describe('KeycloakClient', () => {
  let client: KeycloakClient;

  beforeEach(() => {
    client = new KeycloakClient({
      url: 'http://keycloak:8080',
      publicUrl: 'https://auth.example.com',
      realm: 'homelab',
      clientId: 'homelab-portal',
      clientSecret: 'secret'
    });
    fetchMock.mockReset();
  });

  it('passwordLogin POSTs to /token with ropc grant', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        access_token: 'at',
        refresh_token: 'rt',
        expires_in: 3600,
        token_type: 'Bearer'
      })
    });

    const tokens = await client.passwordLogin('user@example.com', 'pass123');

    expect(fetchMock).toHaveBeenCalledWith(
      'http://keycloak:8080/realms/homelab/protocol/openid-connect/token',
      expect.objectContaining({
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
      })
    );
    const body = fetchMock.mock.calls[0][1].body as URLSearchParams;
    expect(body.get('grant_type')).toBe('password');
    expect(body.get('username')).toBe('user@example.com');
    expect(body.get('password')).toBe('pass123');
    expect(body.get('client_id')).toBe('homelab-portal');
    expect(body.get('client_secret')).toBe('secret');
    expect(tokens.access_token).toBe('at');
  });

  it('userinfo fetches /userinfo with Bearer token', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        sub: 'user-123',
        email: 'user@example.com',
        given_name: 'Test',
        family_name: 'User',
        name: 'Test User'
      })
    });

    const info = await client.userinfo('access-token-value');

    expect(fetchMock).toHaveBeenCalledWith(
      'http://keycloak:8080/realms/homelab/protocol/openid-connect/userinfo',
      expect.objectContaining({
        headers: { Authorization: 'Bearer access-token-value' }
      })
    );
    expect(info.sub).toBe('user-123');
  });

  it('refreshToken POSTs refresh_token grant', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        access_token: 'new-at',
        refresh_token: 'new-rt',
        expires_in: 3600,
        token_type: 'Bearer'
      })
    });

    const tokens = await client.refreshToken('old-refresh');

    const body = fetchMock.mock.calls[0][1].body as URLSearchParams;
    expect(body.get('grant_type')).toBe('refresh_token');
    expect(body.get('refresh_token')).toBe('old-refresh');
    expect(tokens.access_token).toBe('new-at');
  });

  it('throws on failed token request', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 401,
      json: async () => ({
        error: 'invalid_grant',
        error_description: 'Invalid user credentials'
      })
    });

    await expect(client.passwordLogin('user', 'wrong')).rejects.toThrow('Invalid user credentials');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
pnpm test src/lib/server/keycloak.test.ts
```

Expected: FAIL — `Cannot find module './keycloak'`

- [ ] **Step 3: Implement Keycloak client**

Create `apps/homelab-portal/src/lib/server/keycloak.ts`:

```typescript
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pnpm test src/lib/server/keycloak.test.ts
```

Expected: 4 tests passed.

- [ ] **Step 5: Commit**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add apps/homelab-portal/src/lib/server/keycloak.ts apps/homelab-portal/src/lib/server/keycloak.test.ts
git commit -m "feat(portal): Keycloak client for token, userinfo, admin API"
```

---

### Task 5: Admin token cache module

**Files:**
- Create: `apps/homelab-portal/src/lib/server/admin-token.ts`
- Create: `apps/homelab-portal/src/lib/server/admin-token.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/homelab-portal/src/lib/server/admin-token.test.ts`:

```typescript
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { AdminTokenCache } from './admin-token';
import { KeycloakClient } from './keycloak';

describe('AdminTokenCache', () => {
  let kc: KeycloakClient;
  let cache: AdminTokenCache;
  const clientCredsSpy = vi.fn();

  beforeEach(() => {
    clientCredsSpy.mockReset();
    kc = { clientCredentialsToken: clientCredsSpy } as unknown as KeycloakClient;
    cache = new AdminTokenCache(kc);
  });

  it('fetches token on first call', async () => {
    clientCredsSpy.mockResolvedValueOnce({
      access_token: 'admin-at',
      refresh_token: '',
      expires_in: 3600,
      token_type: 'Bearer'
    });

    const token = await cache.get();
    expect(token).toBe('admin-at');
    expect(clientCredsSpy).toHaveBeenCalledTimes(1);
  });

  it('returns cached token if not near expiry', async () => {
    clientCredsSpy.mockResolvedValueOnce({
      access_token: 'admin-at',
      refresh_token: '',
      expires_in: 3600,
      token_type: 'Bearer'
    });

    await cache.get();
    const token2 = await cache.get();
    expect(token2).toBe('admin-at');
    expect(clientCredsSpy).toHaveBeenCalledTimes(1);
  });

  it('refetches when token expires', async () => {
    clientCredsSpy
      .mockResolvedValueOnce({
        access_token: 'first',
        refresh_token: '',
        expires_in: 1,
        token_type: 'Bearer'
      })
      .mockResolvedValueOnce({
        access_token: 'second',
        refresh_token: '',
        expires_in: 3600,
        token_type: 'Bearer'
      });

    await cache.get();
    await new Promise((r) => setTimeout(r, 1100));
    const token = await cache.get();
    expect(token).toBe('second');
    expect(clientCredsSpy).toHaveBeenCalledTimes(2);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
pnpm test src/lib/server/admin-token.test.ts
```

Expected: FAIL — `Cannot find module './admin-token'`

- [ ] **Step 3: Implement admin token cache**

Create `apps/homelab-portal/src/lib/server/admin-token.ts`:

```typescript
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pnpm test src/lib/server/admin-token.test.ts
```

Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add apps/homelab-portal/src/lib/server/admin-token.ts apps/homelab-portal/src/lib/server/admin-token.test.ts
git commit -m "feat(portal): admin token cache for Keycloak service account"
```

---

### Task 6: Config module and singleton instances

**Files:**
- Create: `apps/homelab-portal/src/lib/server/config.ts`

- [ ] **Step 1: Create config module**

Create `apps/homelab-portal/src/lib/server/config.ts`:

```typescript
import { KeycloakClient } from './keycloak';
import { AdminTokenCache } from './admin-token';

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

export const config = {
  keycloakUrl: required('KEYCLOAK_URL'),
  keycloakPublicUrl: required('KEYCLOAK_PUBLIC_URL'),
  keycloakRealm: required('KEYCLOAK_REALM'),
  keycloakClientId: required('KEYCLOAK_CLIENT_ID'),
  keycloakClientSecret: required('KEYCLOAK_CLIENT_SECRET'),
  sessionSecret: required('SESSION_SECRET'),
  sessionEncryptionKey: required('SESSION_ENCRYPTION_KEY'),
  publicBaseUrl: required('PUBLIC_BASE_URL')
};

export const keycloak = new KeycloakClient({
  url: config.keycloakUrl,
  publicUrl: config.keycloakPublicUrl,
  realm: config.keycloakRealm,
  clientId: config.keycloakClientId,
  clientSecret: config.keycloakClientSecret
});

export const adminTokenCache = new AdminTokenCache(keycloak);
```

- [ ] **Step 2: Commit**

```bash
git add apps/homelab-portal/src/lib/server/config.ts
git commit -m "feat(portal): config module with singleton Keycloak client"
```

---

### Task 7: hooks.server.ts — session loading and refresh

**Files:**
- Create: `apps/homelab-portal/src/hooks.server.ts`

- [ ] **Step 1: Create hooks file**

Create `apps/homelab-portal/src/hooks.server.ts`:

```typescript
import type { Handle } from '@sveltejs/kit';
import { redirect } from '@sveltejs/kit';
import { config, keycloak } from '$lib/server/config';
import {
  decodeSession,
  encodeSession,
  SESSION_COOKIE_NAME,
  SESSION_COOKIE_OPTIONS
} from '$lib/server/session';

const PROTECTED_PATHS = ['/profile'];
const REFRESH_THRESHOLD_SECONDS = 60;

export const handle: Handle = async ({ event, resolve }) => {
  const cookie = event.cookies.get(SESSION_COOKIE_NAME);

  if (cookie) {
    try {
      let session = await decodeSession(cookie, config.sessionSecret, config.sessionEncryptionKey);

      const now = Math.floor(Date.now() / 1000);
      if (session.accessTokenExpiresAt - now < REFRESH_THRESHOLD_SECONDS) {
        try {
          const newTokens = await keycloak.refreshToken(session.refreshToken);
          session = {
            ...session,
            accessToken: newTokens.access_token,
            refreshToken: newTokens.refresh_token,
            accessTokenExpiresAt: now + newTokens.expires_in
          };
          const newCookie = await encodeSession(
            session,
            config.sessionSecret,
            config.sessionEncryptionKey
          );
          event.cookies.set(SESSION_COOKIE_NAME, newCookie, SESSION_COOKIE_OPTIONS);
        } catch {
          event.cookies.delete(SESSION_COOKIE_NAME, { path: '/' });
          if (PROTECTED_PATHS.some((p) => event.url.pathname.startsWith(p))) {
            throw redirect(303, `/login?returnTo=${encodeURIComponent(event.url.pathname)}`);
          }
          return resolve(event);
        }
      }

      event.locals.user = {
        sub: session.sub,
        email: session.email,
        name: session.name,
        firstName: session.firstName,
        lastName: session.lastName
      };
    } catch {
      event.cookies.delete(SESSION_COOKIE_NAME, { path: '/' });
    }
  }

  if (PROTECTED_PATHS.some((p) => event.url.pathname.startsWith(p)) && !event.locals.user) {
    throw redirect(303, `/login?returnTo=${encodeURIComponent(event.url.pathname)}`);
  }

  return resolve(event);
};
```

- [ ] **Step 2: Verify build still works**

```bash
cd apps/homelab-portal
pnpm check
```

Expected: no TypeScript errors.

- [ ] **Step 3: Commit**

```bash
git add apps/homelab-portal/src/hooks.server.ts
git commit -m "feat(portal): hooks.server.ts for session loading and refresh"
```

---

### Task 8: Login route

**Files:**
- Create: `apps/homelab-portal/src/routes/login/+page.svelte`
- Create: `apps/homelab-portal/src/routes/login/+page.server.ts`

- [ ] **Step 1: Create login page UI**

Create `apps/homelab-portal/src/routes/login/+page.svelte`:

```svelte
<script lang="ts">
  import { enhance } from '$app/forms';
  let { form } = $props();
</script>

<div class="min-h-screen flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
  <div class="max-w-md w-full space-y-8">
    <div>
      <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900 dark:text-white">
        Sign in to Homelab
      </h2>
    </div>
    <form method="POST" use:enhance class="mt-8 space-y-6">
      {#if form?.error}
        <div class="rounded-md bg-red-50 dark:bg-red-900 p-4">
          <p class="text-sm text-red-800 dark:text-red-200">{form.error}</p>
        </div>
      {/if}
      <div class="rounded-md shadow-sm space-y-4">
        <div>
          <label for="email" class="sr-only">Email</label>
          <input
            id="email"
            name="email"
            type="email"
            autocomplete="email"
            required
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 dark:bg-gray-700 dark:text-white p-3"
            placeholder="Email"
            value={form?.email ?? ''}
          />
        </div>
        <div>
          <label for="password" class="sr-only">Password</label>
          <input
            id="password"
            name="password"
            type="password"
            autocomplete="current-password"
            required
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 dark:bg-gray-700 dark:text-white p-3"
            placeholder="Password"
          />
        </div>
      </div>

      <div>
        <button
          type="submit"
          class="w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          Sign in
        </button>
      </div>
      <div class="flex items-center justify-between text-sm">
        <a href="/forgot-password" class="text-indigo-600 hover:text-indigo-500">Forgot password?</a>
        <a href="/register" class="text-indigo-600 hover:text-indigo-500">Create account</a>
      </div>
    </form>
  </div>
</div>
```

- [ ] **Step 2: Create login server action**

Create `apps/homelab-portal/src/routes/login/+page.server.ts`:

```typescript
import type { Actions } from './$types';
import { fail, redirect } from '@sveltejs/kit';
import { config, keycloak } from '$lib/server/config';
import {
  encodeSession,
  SESSION_COOKIE_NAME,
  SESSION_COOKIE_OPTIONS,
  type SessionData
} from '$lib/server/session';

export const actions: Actions = {
  default: async ({ request, cookies, url }) => {
    const formData = await request.formData();
    const email = formData.get('email')?.toString() ?? '';
    const password = formData.get('password')?.toString() ?? '';

    if (!email || !password) {
      return fail(400, { email, error: 'Email and password are required' });
    }

    try {
      const tokens = await keycloak.passwordLogin(email, password);
      const info = await keycloak.userinfo(tokens.access_token);

      const now = Math.floor(Date.now() / 1000);
      const session: SessionData = {
        sub: info.sub,
        email: info.email,
        name: info.name ?? `${info.given_name ?? ''} ${info.family_name ?? ''}`.trim(),
        firstName: info.given_name ?? '',
        lastName: info.family_name ?? '',
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token,
        accessTokenExpiresAt: now + tokens.expires_in
      };

      const cookie = await encodeSession(
        session,
        config.sessionSecret,
        config.sessionEncryptionKey
      );
      cookies.set(SESSION_COOKIE_NAME, cookie, SESSION_COOKIE_OPTIONS);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Login failed';
      return fail(401, { email, error: message === 'Invalid user credentials' ? 'Invalid email or password' : message });
    }

    const returnTo = url.searchParams.get('returnTo') ?? '/';
    throw redirect(303, returnTo);
  }
};
```

- [ ] **Step 3: Verify build**

```bash
cd apps/homelab-portal
pnpm check && pnpm build
```

Expected: no errors, build succeeds.

- [ ] **Step 4: Commit**

```bash
git add apps/homelab-portal/src/routes/login/
git commit -m "feat(portal): login page with form and OAuth2 ROPC flow"
```

---

### Task 9: Register route

**Files:**
- Create: `apps/homelab-portal/src/routes/register/+page.svelte`
- Create: `apps/homelab-portal/src/routes/register/+page.server.ts`

- [ ] **Step 1: Create register page UI**

Create `apps/homelab-portal/src/routes/register/+page.svelte`:

```svelte
<script lang="ts">
  import { enhance } from '$app/forms';
  let { form } = $props();
</script>

<div class="min-h-screen flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
  <div class="max-w-md w-full space-y-8">
    <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900 dark:text-white">
      Create an account
    </h2>

    {#if form?.success}
      <div class="rounded-md bg-green-50 dark:bg-green-900 p-4">
        <p class="text-sm text-green-800 dark:text-green-200">
          Account created! Please check your email to verify your address.
        </p>
        <a href="/login" class="mt-2 inline-block text-indigo-600 hover:text-indigo-500">Go to sign in</a>
      </div>
    {:else}
      <form method="POST" use:enhance class="mt-8 space-y-6">
        {#if form?.error}
          <div class="rounded-md bg-red-50 dark:bg-red-900 p-4">
            <p class="text-sm text-red-800 dark:text-red-200">{form.error}</p>
          </div>
        {/if}
        <div class="space-y-4">
          <input
            name="firstName"
            type="text"
            required
            placeholder="First name"
            value={form?.firstName ?? ''}
            class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
          />
          <input
            name="lastName"
            type="text"
            required
            placeholder="Last name"
            value={form?.lastName ?? ''}
            class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
          />
          <input
            name="email"
            type="email"
            autocomplete="email"
            required
            placeholder="Email"
            value={form?.email ?? ''}
            class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
          />
          <input
            name="password"
            type="password"
            autocomplete="new-password"
            required
            minlength="8"
            placeholder="Password (min 8 chars)"
            class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
          />
        </div>
        <button
          type="submit"
          class="w-full py-2 px-4 rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
        >
          Create account
        </button>
        <p class="text-center text-sm">
          Already have an account? <a href="/login" class="text-indigo-600 hover:text-indigo-500">Sign in</a>
        </p>
      </form>
    {/if}
  </div>
</div>
```

- [ ] **Step 2: Create register server action**

Create `apps/homelab-portal/src/routes/register/+page.server.ts`:

```typescript
import type { Actions } from './$types';
import { fail } from '@sveltejs/kit';
import { adminTokenCache, keycloak } from '$lib/server/config';

export const actions: Actions = {
  default: async ({ request }) => {
    const formData = await request.formData();
    const email = formData.get('email')?.toString() ?? '';
    const password = formData.get('password')?.toString() ?? '';
    const firstName = formData.get('firstName')?.toString() ?? '';
    const lastName = formData.get('lastName')?.toString() ?? '';

    if (!email || !password || !firstName || !lastName) {
      return fail(400, { email, firstName, lastName, error: 'All fields are required' });
    }
    if (password.length < 8) {
      return fail(400, { email, firstName, lastName, error: 'Password must be at least 8 characters' });
    }

    try {
      const adminToken = await adminTokenCache.get();
      const userId = await keycloak.createUser(adminToken, { email, password, firstName, lastName });
      await keycloak.sendVerifyEmail(adminToken, userId);
      return { success: true };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Registration failed';
      return fail(400, { email, firstName, lastName, error: message });
    }
  }
};
```

- [ ] **Step 3: Verify build**

```bash
cd apps/homelab-portal
pnpm check
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add apps/homelab-portal/src/routes/register/
git commit -m "feat(portal): registration page with Keycloak Admin API"
```

---

### Task 10: Forgot password route

**Files:**
- Create: `apps/homelab-portal/src/routes/forgot-password/+page.svelte`
- Create: `apps/homelab-portal/src/routes/forgot-password/+page.server.ts`

- [ ] **Step 1: Create forgot password UI**

Create `apps/homelab-portal/src/routes/forgot-password/+page.svelte`:

```svelte
<script lang="ts">
  import { enhance } from '$app/forms';
  let { form } = $props();
</script>

<div class="min-h-screen flex items-center justify-center py-12 px-4">
  <div class="max-w-md w-full space-y-8">
    <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900 dark:text-white">
      Reset your password
    </h2>

    {#if form?.success}
      <div class="rounded-md bg-green-50 dark:bg-green-900 p-4">
        <p class="text-sm text-green-800 dark:text-green-200">
          If an account exists with that email, we've sent a password reset link.
        </p>
        <a href="/login" class="mt-2 inline-block text-indigo-600 hover:text-indigo-500">Back to sign in</a>
      </div>
    {:else}
      <form method="POST" use:enhance class="mt-8 space-y-6">
        <input
          name="email"
          type="email"
          required
          placeholder="Email"
          class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
        />
        <button
          type="submit"
          class="w-full py-2 px-4 rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
        >
          Send reset link
        </button>
        <p class="text-center text-sm">
          <a href="/login" class="text-indigo-600 hover:text-indigo-500">Back to sign in</a>
        </p>
      </form>
    {/if}
  </div>
</div>
```

- [ ] **Step 2: Create forgot password server action**

Create `apps/homelab-portal/src/routes/forgot-password/+page.server.ts`:

```typescript
import type { Actions } from './$types';
import { fail } from '@sveltejs/kit';
import { adminTokenCache, keycloak } from '$lib/server/config';

export const actions: Actions = {
  default: async ({ request }) => {
    const formData = await request.formData();
    const email = formData.get('email')?.toString() ?? '';

    if (!email) {
      return fail(400, { error: 'Email is required' });
    }

    try {
      const adminToken = await adminTokenCache.get();
      const user = await keycloak.findUserByEmail(adminToken, email);
      if (user) {
        await keycloak.executeActionsEmail(adminToken, user.id, ['UPDATE_PASSWORD']);
      }
      return { success: true };
    } catch {
      return { success: true };
    }
  }
};
```

- [ ] **Step 3: Verify build**

```bash
cd apps/homelab-portal
pnpm check
```

- [ ] **Step 4: Commit**

```bash
git add apps/homelab-portal/src/routes/forgot-password/
git commit -m "feat(portal): forgot password with Keycloak execute-actions-email"
```

---

### Task 11: Profile edit route

**Files:**
- Create: `apps/homelab-portal/src/routes/profile/+page.svelte`
- Create: `apps/homelab-portal/src/routes/profile/+page.server.ts`

- [ ] **Step 1: Create profile page UI**

Create `apps/homelab-portal/src/routes/profile/+page.svelte`:

```svelte
<script lang="ts">
  import { enhance } from '$app/forms';
  let { data, form } = $props();
</script>

<div class="min-h-screen py-12 px-4">
  <div class="max-w-md mx-auto space-y-8">
    <h2 class="text-3xl font-extrabold text-gray-900 dark:text-white">Your profile</h2>

    {#if form?.success}
      <div class="rounded-md bg-green-50 dark:bg-green-900 p-4">
        <p class="text-sm text-green-800 dark:text-green-200">Profile updated successfully.</p>
      </div>
    {/if}

    {#if form?.error}
      <div class="rounded-md bg-red-50 dark:bg-red-900 p-4">
        <p class="text-sm text-red-800 dark:text-red-200">{form.error}</p>
      </div>
    {/if}

    <form method="POST" action="?/updateProfile" use:enhance class="space-y-4">
      <input
        name="firstName"
        type="text"
        required
        placeholder="First name"
        value={form?.firstName ?? data.user.firstName}
        class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
      />
      <input
        name="lastName"
        type="text"
        required
        placeholder="Last name"
        value={form?.lastName ?? data.user.lastName}
        class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
      />
      <input
        name="email"
        type="email"
        required
        placeholder="Email"
        value={form?.email ?? data.user.email}
        class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
      />
      <button
        type="submit"
        class="w-full py-2 px-4 rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
      >
        Update profile
      </button>
    </form>

    <form method="POST" action="?/changePassword" use:enhance class="space-y-4 pt-8 border-t">
      <h3 class="text-lg font-medium text-gray-900 dark:text-white">Change password</h3>
      <p class="text-sm text-gray-600 dark:text-gray-400">
        We'll send you an email with a link to change your password.
      </p>
      <button
        type="submit"
        class="w-full py-2 px-4 rounded-md text-white bg-gray-600 hover:bg-gray-700"
      >
        Send password change email
      </button>
    </form>

    <div class="pt-8 border-t">
      <a href="/auth/logout" class="text-red-600 hover:text-red-500">Sign out</a>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Create profile server actions**

Create `apps/homelab-portal/src/routes/profile/+page.server.ts`:

```typescript
import type { Actions, PageServerLoad } from './$types';
import { fail, error, redirect } from '@sveltejs/kit';
import { adminTokenCache, config, keycloak } from '$lib/server/config';
import {
  decodeSession,
  encodeSession,
  SESSION_COOKIE_NAME,
  SESSION_COOKIE_OPTIONS
} from '$lib/server/session';

export const load: PageServerLoad = async ({ locals }) => {
  if (!locals.user) {
    throw error(401, 'Unauthorized');
  }
  return { user: locals.user };
};

export const actions: Actions = {
  updateProfile: async ({ request, cookies, locals }) => {
    if (!locals.user) throw redirect(303, '/login');

    const formData = await request.formData();
    const firstName = formData.get('firstName')?.toString() ?? '';
    const lastName = formData.get('lastName')?.toString() ?? '';
    const email = formData.get('email')?.toString() ?? '';

    if (!firstName || !lastName || !email) {
      return fail(400, { firstName, lastName, email, error: 'All fields are required' });
    }

    const cookie = cookies.get(SESSION_COOKIE_NAME);
    if (!cookie) throw redirect(303, '/login');
    const session = await decodeSession(cookie, config.sessionSecret, config.sessionEncryptionKey);

    try {
      await keycloak.updateAccount(session.accessToken, { firstName, lastName, email });

      const updated = {
        ...session,
        firstName,
        lastName,
        email,
        name: `${firstName} ${lastName}`
      };
      const newCookie = await encodeSession(
        updated,
        config.sessionSecret,
        config.sessionEncryptionKey
      );
      cookies.set(SESSION_COOKIE_NAME, newCookie, SESSION_COOKIE_OPTIONS);

      return { success: true };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Update failed';
      return fail(400, { firstName, lastName, email, error: message });
    }
  },

  changePassword: async ({ locals }) => {
    if (!locals.user) throw redirect(303, '/login');

    try {
      const adminToken = await adminTokenCache.get();
      await keycloak.executeActionsEmail(adminToken, locals.user.sub, ['UPDATE_PASSWORD']);
      return { success: true };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to send email';
      return fail(500, { error: message });
    }
  }
};
```

- [ ] **Step 3: Verify build**

```bash
cd apps/homelab-portal
pnpm check
```

- [ ] **Step 4: Commit**

```bash
git add apps/homelab-portal/src/routes/profile/
git commit -m "feat(portal): profile edit with Keycloak Account API"
```

---

### Task 12: Logout route and home page

**Files:**
- Create: `apps/homelab-portal/src/routes/auth/logout/+server.ts`
- Create: `apps/homelab-portal/src/routes/+page.svelte`
- Create: `apps/homelab-portal/src/routes/+page.server.ts`

- [ ] **Step 1: Create logout route**

Create `apps/homelab-portal/src/routes/auth/logout/+server.ts`:

```typescript
import type { RequestHandler } from './$types';
import { redirect } from '@sveltejs/kit';
import { SESSION_COOKIE_NAME } from '$lib/server/session';

export const GET: RequestHandler = async ({ cookies }) => {
  cookies.delete(SESSION_COOKIE_NAME, { path: '/' });
  throw redirect(303, '/');
};
```

- [ ] **Step 2: Create home page**

Create `apps/homelab-portal/src/routes/+page.svelte`:

```svelte
<script lang="ts">
  let { data } = $props();
</script>

<div class="min-h-screen flex items-center justify-center px-4">
  <div class="max-w-md w-full text-center space-y-8">
    <h1 class="text-4xl font-extrabold text-gray-900 dark:text-white">Homelab Portal</h1>

    {#if data.user}
      <div class="space-y-4">
        <p class="text-gray-600 dark:text-gray-400">Signed in as <strong>{data.user.email}</strong></p>
        <div class="flex gap-4 justify-center">
          <a href="/profile" class="px-6 py-3 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
            Profile
          </a>
          <a href="/auth/logout" class="px-6 py-3 bg-gray-600 text-white rounded-md hover:bg-gray-700">
            Sign out
          </a>
        </div>
      </div>
    {:else}
      <div class="space-y-4">
        <p class="text-gray-600 dark:text-gray-400">Please sign in to continue.</p>
        <div class="flex gap-4 justify-center">
          <a href="/login" class="px-6 py-3 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
            Sign in
          </a>
          <a href="/register" class="px-6 py-3 bg-gray-600 text-white rounded-md hover:bg-gray-700">
            Register
          </a>
        </div>
      </div>
    {/if}
  </div>
</div>
```

- [ ] **Step 3: Create home page load function**

Create `apps/homelab-portal/src/routes/+page.server.ts`:

```typescript
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
  return { user: locals.user };
};
```

- [ ] **Step 4: Verify build**

```bash
cd apps/homelab-portal
pnpm check && pnpm build
```

- [ ] **Step 5: Commit**

```bash
git add apps/homelab-portal/src/routes/auth/ apps/homelab-portal/src/routes/+page.svelte apps/homelab-portal/src/routes/+page.server.ts
git commit -m "feat(portal): home page and logout route"
```

---

### Task 13: Healthcheck endpoint

**Files:**
- Create: `apps/homelab-portal/src/routes/healthz/+server.ts`

- [ ] **Step 1: Create healthcheck**

Create `apps/homelab-portal/src/routes/healthz/+server.ts`:

```typescript
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async () => {
  return new Response(JSON.stringify({ status: 'ok' }), {
    headers: { 'Content-Type': 'application/json' }
  });
};
```

- [ ] **Step 2: Commit**

```bash
git add apps/homelab-portal/src/routes/healthz/
git commit -m "feat(portal): /healthz endpoint for container healthcheck"
```

---

### Task 14: Dockerfile

**Files:**
- Create: `apps/homelab-portal/Dockerfile`
- Create: `apps/homelab-portal/.dockerignore`

- [ ] **Step 1: Create Dockerfile**

Create `apps/homelab-portal/Dockerfile`:

```dockerfile
# Stage 1: Build
FROM node:22-alpine AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# Stage 2: Runtime
FROM node:22-alpine
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY --from=builder /app/build ./build
COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile && \
    apk add --no-cache wget
EXPOSE 3000
ENV NODE_ENV=production
ENV PORT=3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://localhost:3000/healthz || exit 1
CMD ["node", "build/index.js"]
```

- [ ] **Step 2: Create .dockerignore**

Create `apps/homelab-portal/.dockerignore`:

```
node_modules
build
.svelte-kit
.env
.env.*
Dockerfile
.dockerignore
.git
.gitignore
README.md
tests
e2e
playwright-report
test-results
vitest.config.ts
playwright.config.ts
```

- [ ] **Step 3: Test Docker build**

```bash
cd apps/homelab-portal
docker build -t homelab-portal:test .
```

Expected: image built successfully.

- [ ] **Step 4: Commit**

```bash
git add apps/homelab-portal/Dockerfile apps/homelab-portal/.dockerignore
git commit -m "feat(portal): multi-stage Dockerfile with healthcheck"
```

---

### Task 15: Portainer stack, Terraform, and Vault secrets

**Files:**
- Create: `terraform/portainer/stacks/homelab-portal.yml`
- Modify: `terraform/portainer/stacks.tf`
- Modify: `terraform/portainer/vault.tf`
- Modify: `terraform/portainer/outputs.tf`

- [ ] **Step 1: Create Portainer stack compose**

Create `terraform/portainer/stacks/homelab-portal.yml`:

```yaml
name: homelab-portal

networks:
  rproxy:
    external: true

services:
  portal:
    image: registry.cf.lcamaral.com/homelab-portal:latest
    container_name: homelab-portal
    hostname: homelab-portal
    networks:
      rproxy:
    environment:
      KEYCLOAK_URL: http://keycloak:8080
      KEYCLOAK_PUBLIC_URL: https://auth.cf.lcamaral.com
      KEYCLOAK_REALM: homelab
      KEYCLOAK_CLIENT_ID: homelab-portal
      KEYCLOAK_CLIENT_SECRET: ${KEYCLOAK_CLIENT_SECRET}
      SESSION_SECRET: ${SESSION_SECRET}
      SESSION_ENCRYPTION_KEY: ${SESSION_ENCRYPTION_KEY}
      PUBLIC_BASE_URL: https://login.cf.lcamaral.com
      NODE_ENV: production
      PORT: "3000"
    restart: on-failure:5
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3000/healthz || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    labels:
      com.centurylinklabs.watchtower.enable: "true"
      com.docker.stack: "homelab-portal"
      com.docker.service: "portal"
      portainer.autodeploy: "false"
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
```

- [ ] **Step 2: Add Vault data source**

Append to `terraform/portainer/vault.tf`:

```hcl
data "vault_kv_secret_v2" "portal" {
  mount = "secret"
  name  = "homelab/portal"
}
```

- [ ] **Step 3: Add stack resource**

Append to `terraform/portainer/stacks.tf`:

```hcl
# ──────────────────────────────────────────────
# Homelab Portal
# SvelteKit login/register/profile portal
# ──────────────────────────────────────────────
resource "portainer_stack" "homelab_portal" {
  name             = "homelab-portal"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/homelab-portal.yml")

  env {
    name  = "KEYCLOAK_CLIENT_SECRET"
    value = data.vault_kv_secret_v2.keycloak_clients.data["homelab_portal_secret"]
  }

  env {
    name  = "SESSION_SECRET"
    value = data.vault_kv_secret_v2.portal.data["session_secret"]
  }

  env {
    name  = "SESSION_ENCRYPTION_KEY"
    value = data.vault_kv_secret_v2.portal.data["session_encryption_key"]
  }
}
```

- [ ] **Step 4: Add to outputs**

Edit `terraform/portainer/outputs.tf` — add to stacks output map:

```hcl
    homelab_portal    = portainer_stack.homelab_portal.name
```

- [ ] **Step 5: Validate Terraform**

```bash
cd terraform/portainer
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add terraform/portainer/stacks/homelab-portal.yml terraform/portainer/stacks.tf terraform/portainer/vault.tf terraform/portainer/outputs.tf
git commit -m "feat(portal): add homelab-portal Portainer stack resource"
```

---

### Task 16: Nginx vhost and Cloudflare DNS + tunnel ingress

**Files:**
- Create: Remote: `/nfs/dockermaster/docker/nginx-rproxy/config/vhost.d/login.cf.lcamaral.com.conf`
- Modify: `terraform/cloudflare/main.tf`

- [ ] **Step 1: Create nginx vhost on dockermaster**

```bash
ssh dockermaster 'cat > /nfs/dockermaster/docker/nginx-rproxy/config/vhost.d/login.cf.lcamaral.com.conf << '"'"'EOF'"'"'
server {
  listen 80;
  server_name login.cf.lcamaral.com;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl;
  http2 on;
  server_name login.cf.lcamaral.com;

  ssl_certificate     /etc/nginx/cert/d.lcamaral.com.fullchain;
  ssl_certificate_key /etc/nginx/cert/d.lcamaral.com.key;
  ssl_protocols       TLSv1.2 TLSv1.3;

  add_header X-Frame-Options DENY always;
  add_header X-Content-Type-Options nosniff always;
  add_header Referrer-Policy strict-origin-when-cross-origin always;

  location / {
    proxy_pass http://homelab-portal:3000;
    proxy_set_header Host $host;
    proxy_http_version 1.1;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_read_timeout 60s;
    client_max_body_size 1m;
  }
}
EOF
echo "vhost created"'
```

- [ ] **Step 2: Add Cloudflare DNS record**

Edit `terraform/cloudflare/main.tf` — add after `auth_cf_tunnel`:

```hcl
# Homelab Portal: login.cf.lcamaral.com -> tunnel
resource "cloudflare_dns_record" "login_cf_tunnel" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "login.cf.lcamaral.com"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bologna.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
```

- [ ] **Step 3: Add tunnel ingress rule**

Edit `terraform/cloudflare/main.tf` — in the `cloudflare_zero_trust_tunnel_cloudflared_config.bologna` config ingress list, add entry after `auth.cf.lcamaral.com`:

```hcl
      {
        hostname = "login.cf.lcamaral.com"
        service  = "https://nginx-rproxy:443"
        origin_request = {
          no_tls_verify = true
        }
      },
```

- [ ] **Step 4: Validate and plan**

```bash
cd terraform/cloudflare
terraform validate
```

Expected: `Success!`

- [ ] **Step 5: Commit**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add terraform/cloudflare/main.tf
git commit -m "feat(portal): add login.cf.lcamaral.com DNS + tunnel ingress"
```

---

### Task 17: GitHub Actions build workflow

**Files:**
- Create: `.github/workflows/build-homelab-portal.yml`

- [ ] **Step 1: Create workflow**

Create `.github/workflows/build-homelab-portal.yml`:

```yaml
name: Build Homelab Portal

on:
  push:
    branches: [main]
    paths:
      - 'apps/homelab-portal/**'
      - '.github/workflows/build-homelab-portal.yml'
  workflow_dispatch:

jobs:
  build:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - name: Log in to local registry
        env:
          REGISTRY_USER: admin
          REGISTRY_PASSWORD: ${{ secrets.REGISTRY_ADMIN_PASSWORD }}
        run: echo "$REGISTRY_PASSWORD" | docker login registry.cf.lcamaral.com -u "$REGISTRY_USER" --password-stdin

      - name: Build image
        working-directory: apps/homelab-portal
        run: |
          docker build \
            -t registry.cf.lcamaral.com/homelab-portal:latest \
            -t registry.cf.lcamaral.com/homelab-portal:${GITHUB_SHA::7} \
            .

      - name: Push image
        run: |
          docker push registry.cf.lcamaral.com/homelab-portal:latest
          docker push registry.cf.lcamaral.com/homelab-portal:${GITHUB_SHA::7}
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build-homelab-portal.yml
git commit -m "feat(portal): GitHub Actions build workflow"
```

---

### Task 18: First deployment — push image and apply Terraform

- [ ] **Step 1: Push branch and trigger build**

```bash
git push -u origin custom-login-portal
```

Expected: branch pushed. The GitHub Actions workflow runs automatically (since `apps/homelab-portal/**` changed).

- [ ] **Step 2: Wait for image build and verify**

```bash
gh run list --workflow="Build Homelab Portal" --limit 1
```

Wait for the run to complete successfully.

- [ ] **Step 3: Verify image in registry**

```bash
export VAULT_ADDR="http://vault.d.lcamaral.com"
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
REG_PW=$(vault kv get -field=admin_password secret/homelab/registry)
/usr/bin/curl -s -u "admin:${REG_PW}" https://registry.cf.lcamaral.com/v2/homelab-portal/tags/list
```

Expected: JSON with `"tags":["latest","<sha>"]`

- [ ] **Step 4: Apply Terraform — Portainer stack**

```bash
cd terraform/portainer
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
PORTAINER_PW=$(vault kv get -field=admin_password secret/homelab/portainer)
terraform apply -auto-approve \
  -target=portainer_stack.homelab_portal \
  -var="portainer_password=${PORTAINER_PW}" \
  -var="vault_token=${VAULT_TOKEN}"
```

Expected: `Apply complete! Resources: 1 added`

- [ ] **Step 5: Apply Terraform — Cloudflare**

```bash
cd ../cloudflare
CF_TOKEN=$(vault kv get -field=api_token secret/homelab/cloudflare)
DH_KEY=$(vault kv get -field=api_token secret/homelab/dreamhost)
terraform apply -auto-approve \
  -var="cloudflare_api_token=${CF_TOKEN}" \
  -var="dreamhost_api_key=${DH_KEY}"
```

Expected: `Apply complete! Resources: 1 added, 1 changed`

- [ ] **Step 6: Reload nginx**

```bash
ssh dockermaster 'docker exec rproxy nginx -t && docker exec rproxy nginx -s reload'
```

Expected: `configuration file /etc/nginx/nginx.conf test is successful`

- [ ] **Step 7: Verify portal is reachable**

```bash
sleep 30
/usr/bin/curl -s -o /dev/null -w "%{http_code}" https://login.cf.lcamaral.com/
```

Expected: `200`

- [ ] **Step 8: Verify healthcheck**

```bash
/usr/bin/curl -s https://login.cf.lcamaral.com/healthz
```

Expected: `{"status":"ok"}`

- [ ] **Step 9: Test login flow end-to-end**

Open in browser: `https://login.cf.lcamaral.com/`
- Click "Sign in"
- Enter credentials for your Keycloak user
- Verify redirect to `/` shows profile card
- Click "Profile", verify page loads with your data
- Click "Sign out", verify session cleared

- [ ] **Step 10: Commit deployment verification**

If any tweaks needed during test, commit them now. Otherwise skip.

---

### Task 19: Update STATUS.md and CLAUDE.md

**Files:**
- Modify: `dockermaster/docker/compose/STATUS.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update STATUS.md**

Add homelab-portal to the Terraform-managed Portainer stacks table (count becomes 20).

- [ ] **Step 2: Update CLAUDE.md**

Add these Vault paths under the Vault paths list:
- `secret/homelab/portal` (session secrets)
- `secret/homelab/keycloak/clients` now includes `homelab_portal_secret`

- [ ] **Step 3: Commit docs**

```bash
git add dockermaster/docker/compose/STATUS.md CLAUDE.md
git commit -m "docs: add homelab-portal to STATUS.md and CLAUDE.md"
```

---

### Task 20: Create PR

- [ ] **Step 1: Push final commits**

```bash
git push
```

- [ ] **Step 2: Create PR**

```bash
gh pr create \
  --title "✨(portal): Homelab login portal (SvelteKit + Keycloak)" \
  --body "## Summary

- New SvelteKit app at login.cf.lcamaral.com providing login, register, forgot password, profile edit
- Uses Keycloak homelab realm as OIDC backend via new homelab-portal client
- Server-side OAuth2 with HTTP-only encrypted session cookies
- Deployed as Portainer stack via Terraform with image from local registry
- GitHub Actions workflow builds on push to main

## Test plan

- [ ] Home page loads at https://login.cf.lcamaral.com/
- [ ] Login with valid credentials redirects to /
- [ ] Login with invalid credentials shows error
- [ ] Register creates new user and sends verification email
- [ ] Forgot password sends reset email
- [ ] Profile edit updates Keycloak user
- [ ] Change password sends email with reset link
- [ ] Logout clears session
- [ ] Terraform plan clean for portainer and cloudflare domains" \
  --base main
```

Expected: PR URL printed.
