// src/shared/constants/brand.ts
//
// Single source of truth for brand defaults across the frontend.
// Backend equivalent: lib/onetime/models/custom_domain/brand_settings.rb

import type { BrandSettings } from '@/schemas/models/domain/brand';
import { CornerStyle, FontFamily } from '@/schemas/models/domain/brand';

export { DEFAULT_BRAND_HEX } from '@/utils/brand-palette';

/** Re-export for consumers that expect DEFAULT_PRIMARY_COLOR */
export { DEFAULT_BRAND_HEX as DEFAULT_PRIMARY_COLOR } from '@/utils/brand-palette';

export const DEFAULT_BUTTON_TEXT_LIGHT = true;
export const DEFAULT_CORNER_CLASS = 'rounded-lg';

/**
 * Neutral brand defaults for self-hosted / white-label instances.
 * These are intentionally NOT OTS-branded — they provide a clean
 * starting point that installations customize via config.
 *
 * The 3-step fallback chain in identityStore uses these as the
 * final fallback (step 3) when neither per-domain nor per-installation
 * brand settings are available.
 *
 * Values are derived from the schema enums (FontFamily, CornerStyle)
 * to prevent drift between constants and schema definitions.
 */
export const NEUTRAL_BRAND_DEFAULTS: Pick<
  BrandSettings,
  | 'primary_color'
  | 'product_name'
  | 'button_text_light'
  | 'corner_style'
  | 'font_family'
  | 'allow_public_homepage'
  | 'allow_public_api'
> = {
  primary_color: '#3B82F6',
  product_name: 'My App',
  button_text_light: DEFAULT_BUTTON_TEXT_LIGHT,
  corner_style: CornerStyle.ROUNDED,
  font_family: FontFamily.SANS,
  allow_public_homepage: true,
  allow_public_api: true,
};
