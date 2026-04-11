import { EncryptJWT, jwtDecrypt } from 'jose';

export interface SessionData {
  sub: string;
  email: string;
  name: string;
  firstName: string;
  lastName: string;
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: number;
}

const MAX_AGE_SECONDS = 60 * 60 * 24 * 7; // 7 days

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

export async function encodeSession(
  data: SessionData,
  signingSecret: string,
  encryptionKey: string
): Promise<string> {
  if (encryptionKey.length !== 64) {
    throw new Error('encryptionKey must be 64 hex chars (32 bytes)');
  }
  if (signingSecret.length < 32) {
    throw new Error('signingSecret must be at least 32 chars');
  }

  const key = hexToBytes(encryptionKey);

  const jwt = await new EncryptJWT({
    data,
    sig: signingSecret.substring(0, 16)
  })
    .setProtectedHeader({ alg: 'dir', enc: 'A256GCM' })
    .setIssuedAt()
    .setExpirationTime(`${MAX_AGE_SECONDS}s`)
    .encrypt(key);

  return jwt;
}

export async function decodeSession(
  cookie: string,
  signingSecret: string,
  encryptionKey: string
): Promise<SessionData> {
  const key = hexToBytes(encryptionKey);

  const { payload } = await jwtDecrypt(cookie, key);

  if (payload.sig !== signingSecret.substring(0, 16)) {
    throw new Error('Session signature mismatch');
  }

  return payload.data as SessionData;
}

export const SESSION_COOKIE_NAME = 'hl_session';

export const SESSION_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: true,
  sameSite: 'lax' as const,
  path: '/',
  maxAge: MAX_AGE_SECONDS
};
