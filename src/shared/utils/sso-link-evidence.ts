// src/shared/utils/sso-link-evidence.ts

/**
 * Connect availability for the Connected Identities panel (#4412, epic #4408).
 *
 * The panel offers one Connect button per configured SSO provider and hides
 * a button only when the account is ALREADY linked to the identity that
 * Connect would produce. "Already linked" is a statement about the callback
 * identity's complete (provider, issuer, uid) tuple, and before the IdP
 * round-trip the UI never holds that tuple:
 *
 * - A bootstrap provider entry carries `route_name` + `display_name` only.
 *   On a tenant host the route name is the PLATFORM route the tenant's IdP
 *   is served through (SsoConfig#platform_route_name), so 'oidc' names a
 *   different IdP on every tenant and on the platform.
 * - Linked rows carry an issuer, but the UI does not know which issuer the
 *   configured route resolves to on this host, and rows under one route name
 *   may hold the platform issuer or another tenant's.
 * - `uid` on the wire is MASKED (routes/identities.rb#mask_uid), so even a
 *   matching issuer cannot prove the same subject.
 *
 * Route-name equality and issuer equality are therefore each compatible with
 * "not linked yet". Hiding Connect on either hides a valid action, so on a
 * tenant surface equivalence is UNKNOWN and Connect stays available. The
 * callback (account_from_omniauth, hooks/omniauth.rb) holds the complete
 * tuple and is the only place that compares it and handles conflicts; nothing
 * here is consulted server-side, so no decision made in this module can
 * authorize a bind or bypass the tenant callback controls in #3849.
 *
 * The one surface with authoritative evidence is the PLATFORM. Platform
 * providers come from env (OIDC_ISSUER, ENTRA_TENANT, ...), so a route name
 * resolves to exactly one IdP, and every stored row was bound through that
 * platform IdP (the tenant callback refuses to bind, omniauth.rb reason
 * `tenant_surface`). A stored row whose provider matches a platform route is
 * therefore an identity from that IdP, and only there does it suppress
 * Connect. When tenant Connect starts binding rows (#3849), this platform
 * rule needs the platform issuer on the provider entry to stay exact.
 */

import type { ConnectedIdentity } from '@/schemas/api/auth/responses/auth';
import type { SsoProvider } from '@/utils/features';

/**
 * Which body of evidence the UI has about configured providers.
 *
 * - 'platform': a route name resolves to exactly one IdP; route equality with
 *   a stored row is evidence of an existing link.
 * - 'tenant':   the route is shared with the platform and other tenants; no
 *   pre-callback comparison is evidence of anything.
 */
export type ConnectSurface = 'platform' | 'tenant';

/**
 * Classify the page's surface from the bootstrap `domain_strategy`.
 *
 * 'canonical' and 'subdomain' are operator hosts served with platform
 * providers. 'custom' is a tenant host. Anything else ('invalid', or a
 * missing value) is treated as 'tenant': the fail-safe direction here is to
 * KEEP Connect visible and let the callback decide, which is the opposite of
 * the backend's fail-closed session-surface gate, and correct for the same
 * reason — the UI can only hide an action, never authorize one.
 */
export function connectSurfaceFor(domainStrategy: string | null | undefined): ConnectSurface {
  return domainStrategy === 'canonical' || domainStrategy === 'subdomain' ? 'platform' : 'tenant';
}

/**
 * True only when the UI has authoritative evidence that `provider` is already
 * linked to the account. Unknown equivalence returns false so the Connect
 * action stays available.
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
