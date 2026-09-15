// src/shared/utils/sso-link-evidence.ts

/**
 * Connect availability for the Connected Identities panel (#4412, epic #4408).
 *
 * The panel offers one Connect button per configured SSO route. Until tenant
 * identity linking is implemented server-side (#3849), the callback refuses
 * every connect intent carrying `validated_omniauth_domain_id` with reason
 * `tenant_surface`. The UI must therefore retain the existing conservative
 * route-name suppression on tenant hosts instead of exposing a duplicate-route
 * action that the callback cannot complete.
 *
 * Route-name equality is not proof that the configured tenant IdP and stored
 * identity have the same issuer or subject. It is only the compatibility rule
 * used while tenant binding remains unavailable. Once the callback can bind a
 * tenant identity, suppression must compare server-provided identity evidence
 * rather than a shared platform route name.
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
 * True when an identity already occupies the configured provider route.
 *
 * The surface argument is retained so tenant linking can introduce stronger
 * evidence without another call-site API change. For now both surfaces use
 * route-name suppression because tenant callbacks refuse identity binds.
 */
export function isKnownLinked(
  provider: SsoProvider,
  identities: readonly ConnectedIdentity[],
  _surface: ConnectSurface
): boolean {
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
