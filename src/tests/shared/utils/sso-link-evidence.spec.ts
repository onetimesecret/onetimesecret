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
 * Connect availability semantics.
 *
 * Platform: a route name maps to one configured issuer, so a stored identity
 * with the same route name is the link and Connect is suppressed. Tenant: the
 * client cannot establish tuple equivalence (masked uid, no bootstrap issuer,
 * pairwise subject identifiers make issuer equality meaningless), so Connect
 * is never suppressed and the callback resolves the full tuple. Display
 * heuristic only; not a security control.
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
    // The backend's surface gate refuses on these hosts; the UI's only safe
    // move is to not hide an action the callback is free to refuse.
    expect(connectSurfaceFor('invalid')).toBe('tenant');
    expect(connectSurfaceFor(undefined)).toBe('tenant');
    expect(connectSurfaceFor(null)).toBe('tenant');
    expect(connectSurfaceFor('')).toBe('tenant');
  });
});

describe('isKnownLinked', () => {
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

  describe('tenant surface — equivalence is resolved by the callback', () => {
    it('does not suppress a provider whose route name is already present', () => {
      expect(isKnownLinked(oidc, [row({ provider: 'oidc' })], 'tenant')).toBe(false);
    });

    it('does not suppress on a matching route name under a different issuer', () => {
      expect(
        isKnownLinked(oidc, [row({ provider: 'oidc', issuer: TENANT_A_ISSUER })], 'tenant')
      ).toBe(false);
    });

    it('does not treat issuer equality as evidence (pairwise subject identifiers)', () => {
      // Same issuer, same route: still not proof the callback's `sub` matches
      // the stored (masked) uid. The callback owns the decision.
      const rows = [
        row({ id: 1, provider: 'oidc', issuer: TENANT_A_ISSUER, uid: 'aaaa…1111' }),
        row({ id: 2, provider: 'oidc', issuer: TENANT_A_ISSUER, uid: 'bbbb…2222' }),
      ];
      expect(isKnownLinked(oidc, rows, 'tenant')).toBe(false);
    });

    it('does not suppress with no rows at all', () => {
      expect(isKnownLinked(oidc, [], 'tenant')).toBe(false);
    });
  });
});

describe('connectableSsoProviders', () => {
  const providers = [oidc, entra];

  it('offers every provider on the tenant surface even when every route name is present', () => {
    const rows = [row({ provider: 'oidc' }), row({ id: 2, provider: 'entra' })];
    expect(connectableSsoProviders(providers, rows, 'tenant')).toEqual([oidc, entra]);
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
