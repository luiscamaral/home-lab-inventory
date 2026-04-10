import { KeycloakClient } from './keycloak';
import { AdminTokenCache } from './admin-token';

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

export const config = {
  keycloakUrl: required('KEYCLOAK_URL'),
  keycloakPublicUrl: required('KEYCLOAK_PUBLIC_URL'),
  keycloakRealm: required('KEYCLOAK_REALM'),
  keycloakClientId: required('KEYCLOAK_CLIENT_ID'),
  keycloakClientSecret: required('KEYCLOAK_CLIENT_SECRET'),
  sessionSecret: required('SESSION_SECRET'),
  sessionEncryptionKey: required('SESSION_ENCRYPTION_KEY'),
  publicBaseUrl: required('PUBLIC_BASE_URL')
};

export const keycloak = new KeycloakClient({
  url: config.keycloakUrl,
  publicUrl: config.keycloakPublicUrl,
  realm: config.keycloakRealm,
  clientId: config.keycloakClientId,
  clientSecret: config.keycloakClientSecret
});

export const adminTokenCache = new AdminTokenCache(keycloak);
