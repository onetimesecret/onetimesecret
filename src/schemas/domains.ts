// src/schemas/domains.ts
import { z } from 'zod'
import { baseApiRecordSchema, booleanFromString } from '@/utils/transforms'

/**
 * @fileoverview Domain schemas for API transformation boundaries
 *
 * Key Design Decisions:
 * 1. Input schemas handle API -> App transformation
 * 2. App uses single shared type between stores/components
 * 3. No explicit output schemas - serialize when needed
 *
 * Example flow:
 * API Response -> InputSchema -> Store/Components -> API Request
 */

/**
 * Input schema for brand settings from API
 * Handles string -> boolean coercion from Ruby/JSON
 */
export const brandSettingsInputSchema = baseApiRecordSchema.extend({
  // Core display settings
  primary_color: z.string(),
  instructions_pre_reveal: z.string(),
  instructions_reveal: z.string(),
  instructions_post_reveal: z.string(),

  // Feature flags come as strings from API
  button_text_light: booleanFromString,
  allow_public_homepage: booleanFromString,
  allow_public_api: booleanFromString,

  // UI configuration
  font_family: z.string(),
  corner_style: z.string(),
})

/**
 * Input schema for custom domain from API
 * - Handles nested brand settings
 * - Coerces string booleans to proper booleans
 * - Allows extra fields from API (passthrough)
 */
export const customDomainInputSchema = baseApiRecordSchema.extend({
  domainid: z.string(),
  custid: z.string(),
  display_domain: z.string(),
  base_domain: z.string(),
  subdomain: z.string(),

  // Boolean fields that come as strings from API
  is_apex: booleanFromString,
  verified: booleanFromString,

  // Required domain fields
  trd: z.string(),
  tld: z.string(),
  sld: z.string(),
  _original_value: z.string(),
  txt_validation_host: z.string(),
  txt_validation_value: z.string(),

  // Optional nested objects
  vhost: z.object({
    apx_hit: z.boolean(),
    // ... rest of vhost fields
  }).optional(),

  brand: brandSettingsInputSchema.optional(),
}).passthrough() // Allow extra fields from API

// Export the inferred types for use in stores/components
export type BrandSettings = z.infer<typeof brandSettingsInputSchema>
export type CustomDomain = z.infer<typeof customDomainInputSchema>
