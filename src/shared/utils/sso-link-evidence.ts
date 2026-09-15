// src/shared/utils/sso-link-evidence.ts

/**
 * Connect availability for the Connected Identities panel (#4412, epic #4408).
 *
 * The panel offers one Connect button per configured SSO route. Route-name
 * equality identifies the configured platform provider, but it cannot establish
 * tenant identity equivalence: a tenant can use the same route or issuer with a
 * different OIDC client and therefore a different pairwise subject.
 *
 * The callback alone receives the full `(provider, issuer, uid)` tuple. Tenant
 * surfaces must keep Connect available and let the callback accept an identity
 * already owned by the session account, bind an unclaimed tuple, or refuse a
 * tuple owned by another account.
 */

import type { ConnectedIdentity } from '@/schemas/api/auth/responses/auth';
import type { SsoProvider } from '@/utils/features';

/**
 * Surface classification retained for the tenant-linking work in #3849.
 */
export type ConnectSurface = 'platform' | 'tenant';

/**
 * Classify the page's surface from the bootstrap `domain_strategy`.
 *
 * 'canonical' and 'subdomain' are operator hosts served with platform
 * providers. 'custom' is a tenant host. Anything else ('invalid', or a
 * missing value) is treated as 'tenant'.
 */
export function connectSurfaceFor(domainStrategy: string | null | undefined): ConnectSurface {
  return domainStrategy === 'canonical' || domainStrategy === 'subdomain' ? 'platform' : 'tenant';
}

/**
 * True when the client has enough evidence to suppress this provider.
 *
 * On the platform, a route name identifies the configured provider. On a tenant
 * surface, neither route nor issuer equality proves an equivalent identity
 * because the masked identity payload cannot establish the callback subject.
 */
export function isKnownLinked(
  provider: SsoProvider,
  identities: readonly ConnectedIdentity[],
  surface: ConnectSurface
): boolean {
  return (
    surface === 'platform' &&
    identities.some((identity) => identity.provider === provider.route_name)
  );
}

/**
 * The configured providers the panel should offer a Connect button for.
 */
export function connectableSsoProviders(
  providers: readonly SsoProvider[],
  identities: readonly ConnectedIdentity[],
  surface: ConnectSurface
): SsoProvider[] {
  return providers.filter((provider) => !isKnownLinked(provider, identities, surface));
}
