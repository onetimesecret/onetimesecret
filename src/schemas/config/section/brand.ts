// src/schemas/config/section/brand.ts

/**
 * Brand Configuration Schema
 *
 * Maps to the `brand:` section in config.defaults.yaml
 */

import { z } from 'zod';
import { nullableString } from '../shared/primitives';

/**
 * Brand configuration for white-label customization
 */
const brandSchema = z.object({
  primary_color: nullableString,
  product_name: nullableString,
  product_domain: nullableString,
  support_email: nullableString,
  corner_style: z.enum(['rounded', 'sharp', 'pill']).default('rounded'),
  font_family: z.string().default('sans'),
  button_text_light: z.boolean().default(true),
  allow_public_homepage: z.boolean().default(true),
  allow_public_api: z.boolean().default(true),
  logo_url: nullableString,
  totp_issuer: nullableString,
});

export { brandSchema };
