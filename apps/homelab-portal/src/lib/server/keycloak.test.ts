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
