import { KeycloakClient } from './keycloak';
import { AdminTokenCache } from './admin-token';

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function makeConfig() {
  return {
    keycloakUrl: required('KEYCLOAK_URL'),
    keycloakPublicUrl: required('KEYCLOAK_PUBLIC_URL'),
    keycloakRealm: required('KEYCLOAK_REALM'),
    keycloakClientId: required('KEYCLOAK_CLIENT_ID'),
    keycloakClientSecret: required('KEYCLOAK_CLIENT_SECRET'),
    sessionSecret: required('SESSION_SECRET'),
    sessionEncryptionKey: required('SESSION_ENCRYPTION_KEY'),
    publicBaseUrl: required('PUBLIC_BASE_URL')
  };
}

type Config = ReturnType<typeof makeConfig>;

let _config: Config | null = null;
export const config = new Proxy({} as Config, {
  get(_target, prop) {
    if (!_config) _config = makeConfig();
    return _config[prop as keyof Config];
  }
});

let _keycloak: KeycloakClient | null = null;
export const keycloak = new Proxy({} as KeycloakClient, {
  get(_target, prop) {
    if (!_keycloak) {
      _keycloak = new KeycloakClient({
        url: config.keycloakUrl,
        publicUrl: config.keycloakPublicUrl,
        realm: config.keycloakRealm,
        clientId: config.keycloakClientId,
        clientSecret: config.keycloakClientSecret
      });
    }
    const value = (_keycloak as unknown as Record<string | symbol, unknown>)[prop];
    return typeof value === 'function' ? value.bind(_keycloak) : value;
  }
});

let _adminTokenCache: AdminTokenCache | null = null;
export const adminTokenCache = new Proxy({} as AdminTokenCache, {
  get(_target, prop) {
    if (!_adminTokenCache) _adminTokenCache = new AdminTokenCache(keycloak);
    const value = (_adminTokenCache as unknown as Record<string | symbol, unknown>)[prop];
    return typeof value === 'function' ? value.bind(_adminTokenCache) : value;
  }
});
