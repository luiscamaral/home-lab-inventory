# Homelab Login Portal Design

Date: 2026-04-10
Status: Approved

## Overview

A SvelteKit application at `login.cf.lcamaral.com` that provides login, registration, password reset, and profile editing for homelab users. Uses Keycloak `homelab` realm as the OIDC backend. Replaces Keycloak's default login UI with a custom branded experience.

## Tech Stack

- **Framework:** SvelteKit (Svelte 5)
- **Language:** TypeScript
- **Styling:** Tailwind CSS + Flowbite component library
- **Package manager:** pnpm
- **Runtime:** Node.js 22 (Alpine)
- **Deployment:** Docker container, Terraform-managed Portainer stack

## Architecture

- **Frontend:** SvelteKit SSR pages with Flowbite components
- **Backend:** SvelteKit server routes handling OAuth2 flows server-side
- **Sessions:** HTTP-only signed cookies containing user profile + tokens
- **IdP:** Keycloak `homelab` realm via new `homelab-portal` OIDC client
- **Network:** Docker `rproxy` bridge for direct Keycloak connectivity

## Routes

| Route | Purpose | Protection |
|---|---|---|
| `/` | Home -- profile card or sign-in CTA | Public (shows different content based on session) |
| `/login` | Email + password form | Public |
| `/auth/callback` | OIDC callback handler | Public |
| `/auth/logout` | Clears session, calls Keycloak logout | Public |
| `/register` | Registration form | Public |
| `/forgot-password` | Password reset trigger | Public |
| `/profile` | Edit profile (name, email, password) | Authenticated |

## Components

### Server modules (`src/lib/server/`)

| File | Responsibility |
|---|---|
| `keycloak.ts` | Keycloak API client: token exchange, userinfo, admin API, account API |
| `session.ts` | Encode/decode signed session cookies |
| `oauth.ts` | PKCE challenge generation, state handling |
| `admin-token.ts` | Cached service account token for admin API calls |

### Hooks (`src/hooks.server.ts`)

- Reads `hl_session` cookie on every request
- Decodes and validates session
- Refreshes access token if expired (< 60s remaining)
- Populates `event.locals.user` for authenticated routes
- Redirects `/profile` to `/login` if no session

### UI components (`src/lib/components/`)

| Component | Used on |
|---|---|
| `LoginForm.svelte` | `/login` |
| `RegisterForm.svelte` | `/register` |
| `ForgotPasswordForm.svelte` | `/forgot-password` |
| `ProfileForm.svelte` | `/profile` |
| `Header.svelte` | All pages -- logo, user menu |
| `Layout.svelte` | Tailwind container + dark mode toggle |

## Data Flow

### Login flow

```
1. User visits /login
2. Submits email + password form
3. SvelteKit server action POST /login
4. Server calls Keycloak /token endpoint:
   grant_type=password
   client_id=homelab-portal
   client_secret=<from env>
   username=<email>
   password=<password>
   scope=openid email profile
5. Receives access_token, id_token, refresh_token
6. Server calls /userinfo with access_token to get user profile
7. Server encodes session JWT: {sub, email, name, access_token, refresh_token, exp}
8. Server sets hl_session cookie (HTTP-only, Secure, SameSite=Lax)
9. Redirect to /
```

### Registration flow

```
1. User visits /register
2. Submits {email, password, firstName, lastName}
3. SvelteKit server action POST /register
4. Server obtains admin service account token (cached)
5. Server calls Keycloak Admin API POST /admin/realms/homelab/users:
   {
     username: email,
     email: email,
     firstName: firstName,
     lastName: lastName,
     enabled: true,
     emailVerified: false,
     credentials: [{type: "password", value: password, temporary: false}]
   }
6. Server calls /admin/realms/homelab/users/{id}/send-verify-email
7. Redirect to /login with success message
8. User verifies email via Keycloak link
9. User can now log in
```

Note: New users have no roles assigned -- they cannot access any OIDC app until admin assigns roles in Keycloak admin console. This is the "admin approval" step.

### Password reset flow

```
1. User visits /forgot-password
2. Enters email
3. SvelteKit server action:
   - Look up user by email via Admin API
   - Call PUT /admin/realms/homelab/users/{id}/execute-actions-email
     body: ["UPDATE_PASSWORD"]
4. User receives reset email from Keycloak (via Postfix relay)
5. User clicks link, sets new password on Keycloak UI
6. User returns to /login
```

### Profile edit flow

```
1. User visits /profile (must be authenticated)
2. Form pre-filled from session data
3. User edits firstName, lastName, or email
4. SvelteKit server action:
   - Call Keycloak Account REST API PUT /realms/homelab/account
     with user's access_token as Bearer
   - Update session cookie with new data
5. For password change: trigger Keycloak required action UPDATE_PASSWORD
```

### Session refresh

On each request, `hooks.server.ts`:
1. Reads `hl_session` cookie
2. If present, decodes and validates signature
3. If access_token expires in < 60s, calls Keycloak /token with grant_type=refresh_token
4. Updates session cookie with new tokens
5. Populates `event.locals.user`

## Session Cookie

- Name: `hl_session`
- Flags: HttpOnly, Secure, SameSite=Lax, Path=/
- Signed with `SESSION_SECRET` (HMAC-SHA256)
- Encrypted payload using `SESSION_ENCRYPTION_KEY` (AES-256-GCM) to protect tokens
- Contents:
  ```json
  {
    "sub": "keycloak-user-id",
    "email": "user@example.com",
    "name": "First Last",
    "access_token": "<encrypted>",
    "refresh_token": "<encrypted>",
    "exp": 1775800000
  }
  ```
- Max age: 7 days

## Environment Variables

| Variable | Source | Purpose |
|---|---|---|
| `KEYCLOAK_URL` | Compose | Internal URL for server-side API calls (`http://keycloak:8080`) |
| `KEYCLOAK_PUBLIC_URL` | Compose | External URL for redirects (`https://auth.cf.lcamaral.com`) |
| `KEYCLOAK_REALM` | Compose | Realm name (`homelab`) |
| `KEYCLOAK_CLIENT_ID` | Compose | OIDC client ID (`homelab-portal`) |
| `KEYCLOAK_CLIENT_SECRET` | Vault `homelab/keycloak/clients` | OIDC client secret |
| `SESSION_SECRET` | Vault `homelab/portal` | HMAC signing key for session cookies |
| `SESSION_ENCRYPTION_KEY` | Vault `homelab/portal` | AES key for encrypting tokens in cookies |
| `PUBLIC_BASE_URL` | Compose | External URL of portal (`https://login.cf.lcamaral.com`) |

## Keycloak Setup

A new OIDC client `homelab-portal` will be created in the `homelab` realm with:
- `clientId: homelab-portal`
- `publicClient: false`
- `serviceAccountsEnabled: true` (for admin API calls)
- `directAccessGrantsEnabled: true` (for ROPC login flow)
- `standardFlowEnabled: true` (for OIDC callback flow if needed later)
- `redirectUris: ["https://login.cf.lcamaral.com/auth/callback"]`
- `webOrigins: ["https://login.cf.lcamaral.com"]`
- Service account client roles (from `realm-management` client):
  - `manage-users`
  - `view-users`
  - `query-users`

Client secret stored in Vault at `secret/homelab/keycloak/clients` under key `homelab_portal_secret`.

## File Structure

```
apps/homelab-portal/
  src/
    routes/
      +layout.svelte
      +page.svelte
      login/
        +page.svelte
        +page.server.ts
      register/
        +page.svelte
        +page.server.ts
      forgot-password/
        +page.svelte
        +page.server.ts
      profile/
        +page.svelte
        +page.server.ts
      auth/
        callback/
          +server.ts
        logout/
          +server.ts
    lib/
      server/
        keycloak.ts
        session.ts
        oauth.ts
        admin-token.ts
      components/
        LoginForm.svelte
        RegisterForm.svelte
        ForgotPasswordForm.svelte
        ProfileForm.svelte
        Header.svelte
    hooks.server.ts
    app.d.ts
    app.html
    app.css
  static/
    favicon.png
  Dockerfile
  .dockerignore
  package.json
  pnpm-lock.yaml
  svelte.config.js
  tailwind.config.ts
  tsconfig.json
  vite.config.ts
```

## Docker Image

Multi-stage build:

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
RUN pnpm install --prod --frozen-lockfile
EXPOSE 3000
CMD ["node", "build/index.js"]
```

Image pushed to `registry.cf.lcamaral.com/homelab-portal:latest`.

## Deployment

### Portainer stack (`terraform/portainer/stacks/homelab-portal.yml`)

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
      PORT: 3000
    restart: on-failure:5
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/healthz"]
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

### Terraform resources

- `terraform/portainer/stacks.tf` -- add `portainer_stack.homelab_portal`
- `terraform/portainer/vault.tf` -- add `vault_kv_secret_v2.portal` data source
- `terraform/portainer/outputs.tf` -- add `homelab_portal` to output map
- `terraform/cloudflare/main.tf` -- add DNS record `login.cf.lcamaral.com` + tunnel ingress rule

### Nginx vhost

`dockermaster/docker/compose/nginx-rproxy/config/vhost.d/login.cf.lcamaral.com.conf`:

```nginx
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
```

### Build pipeline

GitHub Actions workflow `.github/workflows/build-homelab-portal.yml`:
- Triggers on push to `main` with changes under `apps/homelab-portal/**`
- Builds Docker image with multi-arch support
- Pushes to `registry.cf.lcamaral.com/homelab-portal:latest` and `:<sha>`
- Watchtower picks up the new `:latest` tag on next scheduled run (4 AM)

## Secrets in Vault

New path: `secret/homelab/portal`

| Key | Purpose | Generation |
|---|---|---|
| `session_secret` | HMAC signing | `openssl rand -hex 32` |
| `session_encryption_key` | AES-256-GCM | `openssl rand -hex 32` (64 hex chars = 32 bytes) |

Also added to `secret/homelab/keycloak/clients`:
| Key | Purpose |
|---|---|
| `homelab_portal_secret` | OIDC client secret |

## Error Handling

| Scenario | Behavior |
|---|---|
| Invalid credentials at `/login` | Form error: "Invalid email or password" |
| Keycloak unreachable | 503 page: "Authentication service temporarily unavailable" |
| Session cookie expired or invalid | Clear cookie, redirect to `/login` |
| User tries to access `/profile` without session | 302 redirect to `/login?returnTo=/profile` |
| Registration fails (email exists) | Form error: "An account with this email already exists" |
| Password reset for non-existent email | Success message anyway (don't leak account existence) |
| Email verification not completed | Login returns error; show "Please check your inbox for verification link" |

## Testing Strategy

Given this is UI + auth code, the most valuable tests are:

1. **E2E (Playwright)** -- one test per user flow:
   - Register -> verify email (mocked) -> login -> view profile
   - Login with invalid creds -> see error
   - Forgot password -> see success -> receive email (mocked)
   - Profile edit -> see updated data
2. **Server unit tests (Vitest)** for `session.ts`, `oauth.ts`, `keycloak.ts`:
   - Session encode/decode roundtrip
   - PKCE challenge verification
   - Token refresh logic
3. **No component tests** for Svelte components -- they're thin wrappers around Flowbite, E2E covers them

Tests run in GitHub Actions before the Docker build step.

## Out of Scope

- OAuth2 proxy functionality (gating other apps behind this login) -- deferred
- Multi-factor authentication (TOTP) -- relies on Keycloak defaults
- Email templates customization -- uses Keycloak's default
- Admin-facing user management UI -- use Keycloak admin console
- Password strength meter -- form-level validation only
- Account deletion self-service -- manual via Keycloak admin
- Internationalization -- English only
