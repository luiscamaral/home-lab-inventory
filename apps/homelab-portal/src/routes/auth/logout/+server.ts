import type { RequestHandler } from './$types';
import { redirect } from '@sveltejs/kit';
import { SESSION_COOKIE_NAME } from '$lib/server/session';

export const GET: RequestHandler = async ({ cookies }) => {
  cookies.delete(SESSION_COOKIE_NAME, { path: '/' });
  throw redirect(303, '/');
};
