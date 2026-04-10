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
