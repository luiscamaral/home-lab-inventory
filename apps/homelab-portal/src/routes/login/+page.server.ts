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
