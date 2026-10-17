// src/sources/ssoProviderIcons.ts
//
// Static icon metadata for SSO sign-in buttons. OIcon renders
// <use href="#<collection>-<name>">, so each entry must name a symbol that
// exists in the matching sprite (see src/tests/sources/ssoProviderIcons.spec.ts).

export interface SsoProviderIconConfig {
  collection: string;
  name: string;
}

/**
 * Brand icon per provider, keyed by route name. Route names are
 * env-configurable (OIDC_ROUTE_NAME etc.), so this matches the DEFAULT
 * route names plus common aliases; anything unrecognized (including
 * generic OIDC) falls back to SSO_FALLBACK_ICON.
 *
 * 'saml' names a protocol, not a brand, so it gets a generic key glyph
 * (#4450) rather than any one IdP's mark.
 */
export const SSO_PROVIDER_ICONS: Record<string, SsoProviderIconConfig> = {
  google: { collection: 'mdi', name: 'google' },
  github: { collection: 'mdi', name: 'github' },
  gitlab: { collection: 'mdi', name: 'gitlab' },
  entra: { collection: 'mdi', name: 'microsoft' },
  microsoft: { collection: 'mdi', name: 'microsoft' },
  apple: { collection: 'mdi', name: 'apple' },
  saml: { collection: 'mdi', name: 'key' },
};

/** Neutral building-office icon for route names with no brand mapping. */
export const SSO_FALLBACK_ICON: SsoProviderIconConfig = {
  collection: 'heroicons',
  name: 'building-office-16-solid',
};

export const ssoProviderIcon = (routeName: string): SsoProviderIconConfig =>
  SSO_PROVIDER_ICONS[routeName] ?? SSO_FALLBACK_ICON;
