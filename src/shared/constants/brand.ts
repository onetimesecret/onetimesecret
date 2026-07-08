// src/shared/constants/brand.ts
//
// Centralized brand constants for the frontend.
// Backend equivalent: lib/onetime/models/custom_domain/brand_settings.rb
// (BrandSettingsConstants).
//
// Brand Value Resolution (3-step fallback chain):
//   1. domain_branding         - Per-domain settings from Redis (custom domain)
//   2. bootstrap config        - Site-wide defaults from backend (OT.conf)
//   3. NEUTRAL_BRAND_DEFAULTS  - Generic neutral theme when bootstrap is absent
//
// Philosophy: step 3 must NEVER show OTS branding. If bootstrap fails to
// provide brand data, the UI degrades to a neutral "Secure Links" blue, not
// accidentally advertising OTS. This supports private-label deployments.
//
// See identityStore.ts for the implementation of this fallback chain.

import { CornerStyle, FontFamily } from '@/shared/utils/brand-helpers';

/**
 * Default value for `button_text_light`.
 *
 * Light text reads well on most saturated brand colors; the WCAG contrast
 * checker can override this per-domain when a brand color is too pale.
 */
export const DEFAULT_BUTTON_TEXT_LIGHT = true;

/**
 * Default Tailwind class for rounded UI corners.
 *
 * Used by `useBranding` consumers that need a corner class before brand
 * settings have resolved.
 */
export const DEFAULT_CORNER_CLASS = 'rounded-lg';

/**
 * Neutral brand defaults for private-label / unbranded instances.
 *
 * These are intentionally NOT OTS-branded. They provide a clean, generic
 * appearance when neither per-domain branding nor bootstrap config supply
 * brand values.
 *
 * - `primary_color: '#3B82F6'` — generic blue, avoids OTS orange
 * - `product_name: 'Secure Links'` — neutral placeholder for customization
 *
 * Values for enum-typed fields are derived from the schema enums to
 * prevent drift between constants and schema definitions.
 *
 * @see src/schemas/contracts/custom-domain/brand-config.ts
 */
export const NEUTRAL_BRAND_DEFAULTS = {
  primary_color: '#3B82F6',
  product_name: 'Secure Links',
  button_text_light: DEFAULT_BUTTON_TEXT_LIGHT,
  corner_style: CornerStyle.ROUNDED,
  font_family: FontFamily.SANS,
} as const;

export type NeutralBrandDefaults = typeof NEUTRAL_BRAND_DEFAULTS;

/**
 * Resolves the display product name, neutral-safe.
 *
 * Applies step 2 → step 3 of the fallback chain for the product name:
 * the per-installation `brand_product_name` (from OT.conf) when set, otherwise
 * the neutral `NEUTRAL_BRAND_DEFAULTS.product_name` ('Secure Links'). Per the
 * philosophy above it MUST NEVER emit OTS branding — an unbranded install
 * degrades to the neutral default, never a hardcoded "Onetime Secret".
 *
 * An empty string is treated as unset (`||`, not `??`) so a blank product-name
 * config falls through to the neutral default instead of rendering an empty
 * name. This is the single source of truth for the product-name fallback that
 * `identityStore.productName` (component surfaces) and `usePageTitle`
 * (router-guard context, i18n-free) both build on.
 */
export function resolveProductName(
  brandProductName: string | null | undefined
): string {
  return brandProductName || NEUTRAL_BRAND_DEFAULTS.product_name;
}

/**
 * Sentinel for the neutral, brand-agnostic default logo component.
 *
 * The masthead's logo loader treats a `.vue` URL as a component to dynamically
 * import; this value points at the bundled neutral `DefaultLogo.vue` (the
 * keyhole mark — the OTS-company maruhi 秘 mark is never the default). Centralized
 * here so the resolver (`identityStore.logoSource`) and its consumers agree on
 * one sentinel rather than each hardcoding the string.
 *
 * Stays the terminal fallback on custom domains, and the hard-fallback when a
 * dynamic import fails, so a misconfigured build degrades to neutral — never
 * to an operator-branded component (see `RESOLVED_LOGO_COMPONENT`).
 */
export const DEFAULT_LOGO_COMPONENT = 'DefaultLogo.vue';

/**
 * Build-time operator override for the default masthead logo component,
 * selected via `VITE_LOGO_COMPONENT` (baked at compile time — deliberately a
 * `VITE_` build var, NOT a runtime `BRAND_*` setting, since the choice is a
 * property of the brand build, not per-deployment config).
 *
 * Conventions & constraints for an override component:
 *  - Value is the bare component name (e.g. `OnetimeSecretLogo`); the `.vue`
 *    suffix is normalized on so the masthead's `endsWith('.vue')` detection and
 *    dynamic-import loader keep working unchanged.
 *  - Must be a `.vue` file in `src/shared/components/logos/` (the loader's glob
 *    root). A name that doesn't resolve fails the Vite build (existence check
 *    in vite.config.ts) rather than silently degrading at runtime.
 *  - Must accept the `LogoConfig` props the masthead binds (size, href,
 *    showSiteName, siteName, alt/ariaLabel, isUserPresent, isColonelArea).
 *  - Applies ONLY as the install (canonical/subdomain) terminal fallback. It
 *    never displaces a tenant's uploaded logo and is suppressed on custom
 *    domains — the resolver, not the component, enforces this so operator
 *    branding cannot leak onto a tenant domain.
 *
 * Unset → the neutral `DEFAULT_LOGO_COMPONENT`.
 */
// `import.meta.env` is undefined outside Vite (e.g. the OpenAPI generator runs
// this module under tsx), so optional-chain the whole access rather than just
// the value — unset resolves to the neutral DEFAULT_LOGO_COMPONENT below.
const buildLogoComponent = import.meta.env?.VITE_LOGO_COMPONENT?.trim();
export const RESOLVED_LOGO_COMPONENT = buildLogoComponent
  ? `${buildLogoComponent.replace(/\.vue$/, '')}.vue`
  : DEFAULT_LOGO_COMPONENT;
