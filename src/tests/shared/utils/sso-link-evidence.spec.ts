// src/tests/shared/utils/sso-link-evidence.spec.ts

import { describe, it, expect } from 'vitest';
import type { ConnectedIdentity } from '@/schemas/api/auth/responses/auth';
import type { SsoProvider } from '@/utils/features';
import {
  connectSurfaceFor,
  connectableSsoProviders,
  isKnownLinked,
} from '@/shared/utils/sso-link-evidence';

/**
 * Connect availability semantics (#4412, epic #4408).
 *
 * The UI never holds the callback identity's full (provider, issuer, uid)
 * tuple before the IdP round-trip: the provider entry has no issuer, and the
 * wire uid is masked. So on a tenant surface neither route-name equality nor
 * issuer equality is evidence of an existing link, and Connect must stay
 * available for the callback to decide. On the platform surface a route name
 * resolves to exactly one IdP, so a matching stored row is authoritative and
 * suppresses Connect.
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
  describe('tenant surface — equivalence is unknown before the callback', () => {
    it('does not treat a shared route name as an existing link', () => {
      // A platform-issuer row under 'oidc' says nothing about the tenant's
      // own IdP, which is served through the same route name.
      expect(isKnownLinked(oidc, [row({ provider: 'oidc' })], 'tenant')).toBe(false);
    });

    it('does not treat a shared issuer as an existing link', () => {
      // Even a row on the tenant's issuer cannot prove the same subject: the
      // uid is masked on the wire and the callback identity is not known yet.
      expect(
        isKnownLinked(oidc, [row({ provider: 'oidc', issuer: TENANT_A_ISSUER })], 'tenant')
      ).toBe(false);
    });

    it('does not treat two rows on one issuer with different uids as a link', () => {
      const rows = [
        row({ id: 1, provider: 'oidc', issuer: TENANT_A_ISSUER, uid: 'aaaa…1111' }),
        row({ id: 2, provider: 'oidc', issuer: TENANT_A_ISSUER, uid: 'bbbb…2222' }),
      ];
      expect(isKnownLinked(oidc, rows, 'tenant')).toBe(false);
    });

    it('keeps Connect available with no rows at all', () => {
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

  it('offers every configured provider on the tenant surface regardless of rows', () => {
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
