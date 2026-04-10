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
