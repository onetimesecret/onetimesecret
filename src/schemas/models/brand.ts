// src/schemas/models/brand.ts
import { z } from 'zod'
import { baseApiRecordSchema, booleanFromString } from '@/utils/transforms'
import type { BaseApiRecord } from '@/types/api/responses'

/**
 * @fileoverview Brand settings schema for API transformation boundaries
 *
 * Key Design Decisions:
 * 1. Input schemas handle API -> App transformation
 * 2. App uses single shared type between stores/components
 * 3. No explicit output schemas - serialize when needed
 *
 * Type Flow:
 * API Response (strings) -> InputSchema -> Store/Components -> API Request
 *                          ^                                ^
 *                          |                                |
 *                       transform                       serialize
 *
 * Validation Rules:
 * - Boolean fields come as strings from Ruby/Redis ('true'/'false')
 * - Colors must be valid hex codes
 * - Font family and corner style from predefined options
 */

// Font family options matching UI constraints
export const FontFamily = {
  ARIAL: 'Arial, sans-serif',
  HELVETICA: 'Helvetica, Arial, sans-serif',
  GEORGIA: 'Georgia, serif',
  TIMES: 'Times New Roman, serif'
} as const

// Corner style options matching UI constraints
export const CornerStyle = {
  ROUNDED: 'rounded',
  SHARP: 'sharp'
} as const

/**
 * Input schema for brand settings from API
 * - Handles string -> boolean coercion from Ruby/Redis
 * - Validates color format
 * - Constrains font and corner style options
 */
export const brandSettingsInputSchema = baseApiRecordSchema.extend({
  // Core display settings
  primary_color: z.string().regex(/^#[0-9A-F]{6}$/i, 'Invalid hex color'),
  instructions_pre_reveal: z.string(),
  instructions_reveal: z.string(),
  instructions_post_reveal: z.string(),

  // Boolean fields that come as strings from API
  button_text_light: booleanFromString,
  allow_public_homepage: booleanFromString,
  allow_public_api: booleanFromString,

  // UI configuration with constrained values
  font_family: z.enum([
    FontFamily.ARIAL,
    FontFamily.HELVETICA,
    FontFamily.GEORGIA,
    FontFamily.TIMES
  ]),
  corner_style: z.enum([
    CornerStyle.ROUNDED,
    CornerStyle.SHARP
  ])
})

/**
 * Image properties schema for brand assets
 */
export const imagePropsSchema = baseApiRecordSchema.extend({
  encoded: z.string(),
  content_type: z.string(),
  filename: z.string(),
  bytes: z.number().optional(),
  width: z.number().optional(),
  height: z.number().optional(),
  ratio: z.number().optional()
})

// Export inferred types for use in stores/components
export type BrandSettings = z.infer<typeof brandSettingsInputSchema> & BaseApiRecord
export type ImageProps = z.infer<typeof imagePropsSchema> & BaseApiRecord
