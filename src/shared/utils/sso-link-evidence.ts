// src/shared/utils/sso-link-evidence.ts

/**
 * Connect availability for the Connected Identities panel.
 *
 * The panel offers one Connect button per configured SSO route and hides the
 * button only when the client already has evidence that the route is linked.
 * What counts as evidence depends on the surface:
 *
 * - Platform surface ('canonical' / 'subdomain' hosts): every provider route
 *   name maps to exactly one configured issuer, so a stored identity with the
 *   same route name IS the link. Suppress on route-name match.
 * - Tenant surface ('custom' hosts): equivalence cannot be established
 *   client-side. Identities are keyed on the full (provider, issuer, uid)
 *   tuple, the identities API masks `uid`, and the bootstrap provider carries
 *   no issuer. Issuer equality alone is not evidence either: with OpenID
 *   Connect pairwise subject identifiers the same issuer hands a different
 *   `sub` to each client, so a platform and a tenant on one IdP produce
 *   distinct tuples. Never suppress; the callback resolves the returned tuple
 *   (idempotent for a tuple the session account already owns, refused with
 *   `identity_owned_elsewhere` otherwise). See
 *   docs/authentication/per-domain-sso.md, "Identity linking and surface
 *   isolation".
 *
 * This is a display heuristic, not a security control. Hiding a button never
 * prevents a bind; showing one never permits it. The server callback's
 * ownership check is the sole authority.
 */

import type { ConnectedIdentity } from '@/schemas/api/auth/responses/auth';
import type { SsoProvider } from '@/utils/features';

/**
 * Surface classification. Drives which linked-identity evidence the panel
 * may act on (see the file header).
 */
export type ConnectSurface = 'platform' | 'tenant';

/**
 * Classify the page's surface from the bootstrap `domain_strategy`.
 *
 * 'canonical' and 'subdomain' are operator hosts served with platform
 * providers. 'custom' is a tenant host. Anything else ('invalid', or a
 * missing value) is treated as 'tenant': that keeps Connect visible, and the
 * backend surface gate still refuses any connect it should not accept.
 */
export function connectSurfaceFor(domainStrategy: string | null | undefined): ConnectSurface {
  return domainStrategy === 'canonical' || domainStrategy === 'subdomain' ? 'platform' : 'tenant';
}

/**
 * True when the client has evidence that the configured provider route is
 * already linked to the current account.
 *
 * Platform: a stored identity with the same route name. Tenant: never (the
 * masked uid and absent issuer leave no client-side evidence; the callback
 * decides).
 */
export function isKnownLinked(
  provider: SsoProvider,
  identities: readonly ConnectedIdentity[],
  surface: ConnectSurface
): boolean {
  if (surface !== 'platform') return false;
  return identities.some((identity) => identity.provider === provider.route_name);
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
