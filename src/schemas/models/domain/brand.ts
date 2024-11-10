// src/schemas/models/domain/brand.ts
import { baseNestedRecordSchema, type BaseNestedRecord } from '@/schemas/base'
import { booleanFromString } from '@/utils/transforms'
import { z } from 'zod'

/**
 * @fileoverview Brand settings schema for API transformation boundaries
 *
 * Model Organization:
 * While Brand is a nested model of Domain, it exists as a separate file because:
 * 1. It has distinct validation rules and complex type definitions
 * 2. It maintains separation of concerns and code organization
 * 3. It allows direct imports of Brand-specific logic where needed
 * 4. It keeps Domain model focused on core domain logic
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
  TIMES: 'Times New Roman, serif',
  SANS: 'sans-serif',
  SERIF: 'serif',
  BRAND: 'brand',
} as const

// Corner style options matching UI constraints
export const CornerStyle = {
  ROUNDED: 'rounded',
  SHARP: 'sharp',
  PILL: 'pill',
} as const

/**
 * Input schema for brand settings from API
 * - Handles string -> boolean coercion from Ruby/Redis
 * - Validates color format
 * - Constrains font and corner style options
 */
export const brandSettingsInputSchema = z.object({
  // Core display settings
  primary_color: z.string().regex(/^#[0-9A-F]{6}$/i, 'Invalid hex color'),
  colour: z.string().optional(), // Legacy field
  instructions_pre_reveal: z.string().optional(),
  instructions_reveal: z.string().optional(),
  instructions_post_reveal: z.string().optional(),
  description: z.string().optional(),


  // Boolean fields that come as strings from API
  button_text_light: booleanFromString.optional().default(false),
  allow_public_homepage: booleanFromString.optional().default(false),
  allow_public_api: booleanFromString.optional().default(false),

  // UI configuration with constrained values
  font_family: z.enum([
    FontFamily.ARIAL,
    FontFamily.HELVETICA,
    FontFamily.GEORGIA,
    FontFamily.TIMES,
    FontFamily.SERIF,
    FontFamily.SANS,
    FontFamily.BRAND,
  ]).optional(),

  corner_style: z.enum([
    CornerStyle.ROUNDED,
    CornerStyle.SHARP,
    CornerStyle.PILL
  ]).optional(),

  // Image related fields
  image_content_type: z.string().optional(),
  image_encoded: z.string().optional(),
  image_filename: z.string().optional(),
}).merge(baseNestedRecordSchema);

/**
 * Image properties schema for brand assets
 */
export const imagePropsSchema = z.object({
  encoded: z.string().optional(),
  content_type: z.string().optional(),
  filename: z.string().optional(),
  bytes: z.number().optional(),
  width: z.number().optional(),
  height: z.number().optional(),
  ratio: z.number().optional(),
}).merge(baseNestedRecordSchema).strip();

// Export inferred types for use in stores/components
export type BrandSettings = z.infer<typeof brandSettingsInputSchema> & BaseNestedRecord;
export type ImageProps = z.infer<typeof imagePropsSchema> & BaseNestedRecord;
