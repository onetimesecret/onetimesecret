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
// provide brand data, the UI degrades to a neutral "My App" blue, not
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
 * - `product_name: 'My App'` — neutral placeholder for customization
 *
 * Values for enum-typed fields are derived from the schema enums to
 * prevent drift between constants and schema definitions.
 *
 * @see src/schemas/contracts/custom-domain/brand-config.ts
 */
export const NEUTRAL_BRAND_DEFAULTS = {
  primary_color: '#3B82F6',
  product_name: 'My App',
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
 * the neutral `NEUTRAL_BRAND_DEFAULTS.product_name` ('My App'). Per the
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
