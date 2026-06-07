// src/schemas/contracts/config/section/brand.ts

/**
 * Brand Configuration Schema
 *
 * Maps to the `brand:` section in config.defaults.yaml. This represents
 * the YAML-shape of brand defaults supplied by operator config (OT.conf).
 * The bootstrap payload flattens these into `brand_*` fields — see
 * `bootstrapSchema` for the runtime contract.
 *
 * Per #3049 the shipped defaults are intentionally neutral: no `brand:`
 * block ships in `etc/defaults/config.defaults.yaml`. Operators set
 * `BRAND_*` ENV vars to populate this section. When absent, the frontend
 * falls back to `NEUTRAL_BRAND_DEFAULTS`.
 *
 * @see src/shared/constants/brand.ts — frontend neutral fallback
 * @see src/schemas/contracts/bootstrap.ts — flattened bootstrap payload
 */

import { z } from 'zod';
import { cornerStyleValues, fontFamilyValues } from '../../custom-domain/brand-config';
import { nullableString } from '../shared/primitives';

/**
 * Brand configuration for white-label customization.
 *
 * Mirrors the `brand:` YAML section. All fields are optional/nullable so
 * operator config can supply any subset; missing values resolve through
 * `NEUTRAL_BRAND_DEFAULTS` at the store layer.
 */
const brandSchema = z.object({
  primary_color: nullableString,
  product_name: nullableString,
  product_domain: nullableString,
  support_email: nullableString,
  footer_text: nullableString,
  logo_url: nullableString,
  logo_dark_url: nullableString,
  favicon_url: nullableString,
  totp_issuer: nullableString,
  corner_style: z.enum(cornerStyleValues).optional(),
  font_family: z.enum(fontFamilyValues).optional(),
  button_text_light: z.boolean().optional(),
});

export type BrandConfig = z.infer<typeof brandSchema>;

export { brandSchema };
