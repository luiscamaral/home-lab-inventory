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
