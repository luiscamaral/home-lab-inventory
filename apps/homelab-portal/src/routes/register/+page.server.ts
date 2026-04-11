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
