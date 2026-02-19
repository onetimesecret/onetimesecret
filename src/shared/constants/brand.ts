// src/shared/constants/brand.ts
//
// Centralized brand constants for the frontend.
// Backend equivalent: lib/onetime/models/custom_domain/brand_settings.rb (BrandSettingsConstants)
//
// Brand Value Resolution (3-step fallback chain):
//   1. domain_branding      - Per-domain settings from Redis (custom domain branding)
//   2. bootstrap config     - Site-wide defaults from backend (OT.conf via BrandSettingsConstants)
//   3. NEUTRAL_BRAND_DEFAULTS - Generic neutral theme when bootstrap completely fails
//
// Philosophy: Step 3 should NEVER show OTS branding. If bootstrap fails to provide
// brand data, the UI degrades to a neutral "My App" blue appearance, not accidentally
// advertising OTS. This supports private-label / private-label deployments.
//
// See identityStore.ts for the implementation of this fallback chain.

import { CornerStyle, FontFamily } from '@/schemas/models/domain/brand';

/**
 * @deprecated Legacy OTS-branded fallback. Use NEUTRAL_BRAND_DEFAULTS instead.
 * This constant remains only for:
 * - Palette generator tests that validate the OTS brand color specifically
 * - SecretPreview.vue which intentionally displays OTHER domain's brand
 * Do NOT use this as a fallback in brand resolution logic.
 */
export { DEFAULT_BRAND_HEX } from '@/utils/brand-palette';

/** @deprecated Use NEUTRAL_BRAND_DEFAULTS.primary_color instead */
export { DEFAULT_BRAND_HEX as DEFAULT_PRIMARY_COLOR } from '@/utils/brand-palette';

export const DEFAULT_BUTTON_TEXT_LIGHT = true;
export const DEFAULT_CORNER_CLASS = 'rounded-lg';

/**
 * Neutral brand defaults for private-label / private-label instances.
 * These are intentionally NOT OTS-branded — they provide a clean, generic
 * appearance when bootstrap data is unavailable.
 *
 * Used as the final fallback (step 3) in identityStore when neither per-domain
 * branding nor bootstrap config provide brand values.
 *
 * Color: Blue (#3B82F6) - Generic, professional, avoids OTS orange
 * Name: "My App" - Neutral placeholder for customization
 *
 * Values are derived from schema enums (FontFamily, CornerStyle) to prevent
 * drift between constants and schema definitions.
 */
export const NEUTRAL_BRAND_DEFAULTS = {
  primary_color: '#3B82F6' as const,
  product_name: 'My App' as const,
  button_text_light: DEFAULT_BUTTON_TEXT_LIGHT,
  corner_style: CornerStyle.ROUNDED,
  font_family: FontFamily.SANS,
  allow_public_homepage: true,
  allow_public_api: true,
} as const;
