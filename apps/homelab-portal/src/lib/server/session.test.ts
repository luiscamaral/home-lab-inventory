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
