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
