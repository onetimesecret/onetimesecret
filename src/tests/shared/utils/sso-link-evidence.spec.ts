// src/tests/shared/utils/sso-link-evidence.spec.ts

import type { ConnectedIdentity } from '@/schemas/api/auth/responses/auth';
import {
  connectSurfaceFor,
  connectableSsoProviders,
  isKnownLinked,
} from '@/shared/utils/sso-link-evidence';
import type { SsoProvider } from '@/utils/features';
import { describe, expect, it } from 'vitest';

/**
 * Connect availability semantics (#4412, epic #4408).
 *
 * Platform routes can use route-name suppression. Tenant routes remain visible
 * because the client does not receive the complete subject and cannot establish
 * equivalence before the callback.
 */

const PLATFORM_ISSUER = 'https://login.microsoftonline.com/platform-tenant/v2.0';
const TENANT_A_ISSUER = 'https://login.microsoftonline.com/tenant-a/v2.0';

const oidc: SsoProvider = { route_name: 'oidc', display_name: 'Acme SSO' };
const entra: SsoProvider = { route_name: 'entra', display_name: 'Microsoft' };

const row = (overrides: Partial<ConnectedIdentity> = {}): ConnectedIdentity => ({
  id: 1,
  provider: 'oidc',
  issuer: PLATFORM_ISSUER,
  uid: 'abcd…wxyz',
  ...overrides,
});

describe('connectSurfaceFor', () => {
  it('classifies operator hosts as the platform surface', () => {
    expect(connectSurfaceFor('canonical')).toBe('platform');
    expect(connectSurfaceFor('subdomain')).toBe('platform');
  });

  it('classifies a custom domain as the tenant surface', () => {
    expect(connectSurfaceFor('custom')).toBe('tenant');
  });

  it('fails toward keeping Connect visible for an invalid or missing strategy', () => {
    // The backend's session-surface gate refuses on these hosts; the UI's
    // only safe move is to not hide an action the callback is free to refuse.
    expect(connectSurfaceFor('invalid')).toBe('tenant');
    expect(connectSurfaceFor(undefined)).toBe('tenant');
    expect(connectSurfaceFor(null)).toBe('tenant');
    expect(connectSurfaceFor('')).toBe('tenant');
  });
});

describe('isKnownLinked', () => {
  describe('tenant surface — callback determines full-tuple ownership', () => {
    it('does not infer equivalence from a matching route name', () => {
      expect(isKnownLinked(oidc, [row({ provider: 'oidc' })], 'tenant')).toBe(false);
    });

    it('does not infer equivalence from a matching route and issuer', () => {
      expect(
        isKnownLinked(oidc, [row({ provider: 'oidc', issuer: TENANT_A_ISSUER })], 'tenant')
      ).toBe(false);
    });

    it('does not infer equivalence from masked uid values', () => {
      const rows = [
        row({ id: 1, provider: 'oidc', issuer: TENANT_A_ISSUER, uid: 'aaaa…1111' }),
        row({ id: 2, provider: 'oidc', issuer: TENANT_A_ISSUER, uid: 'bbbb…2222' }),
      ];
      expect(isKnownLinked(oidc, rows, 'tenant')).toBe(false);
    });

    it('keeps Connect available with no identities', () => {
      expect(isKnownLinked(oidc, [], 'tenant')).toBe(false);
    });
  });

  describe('platform surface — route name resolves to a single IdP', () => {
    it('treats a row with the same route name as an exact known link', () => {
      expect(isKnownLinked(entra, [row({ provider: 'entra' })], 'platform')).toBe(true);
    });

    it('does not treat a row from a different route as a link', () => {
      expect(isKnownLinked(entra, [row({ provider: 'oidc' })], 'platform')).toBe(false);
    });

    it('keeps Connect available with no rows at all', () => {
      expect(isKnownLinked(entra, [], 'platform')).toBe(false);
    });
  });
});

describe('connectableSsoProviders', () => {
  const providers = [oidc, entra];

  it('keeps all tenant providers available until the callback resolves the tuple', () => {
    const rows = [row({ provider: 'oidc' }), row({ id: 2, provider: 'entra' })];
    expect(connectableSsoProviders(providers, rows, 'tenant')).toEqual(providers);
  });

  it('drops only the exact known link on the platform surface', () => {
    const rows = [row({ provider: 'entra' })];
    expect(connectableSsoProviders(providers, rows, 'platform')).toEqual([oidc]);
  });

  it('offers nothing on the platform surface when every provider is linked', () => {
    const rows = [row({ provider: 'oidc' }), row({ id: 2, provider: 'entra' })];
    expect(connectableSsoProviders(providers, rows, 'platform')).toEqual([]);
  });

  it('returns a new array and leaves the input untouched', () => {
    const rows = [row({ provider: 'entra' })];
    const result = connectableSsoProviders(providers, rows, 'platform');
    expect(result).not.toBe(providers);
    expect(providers).toEqual([oidc, entra]);
  });
});
