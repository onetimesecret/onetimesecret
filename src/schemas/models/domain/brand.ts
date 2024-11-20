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



/**
 * Generic configuration type for option sets
 */
type OptionConfig<T extends string> = Record<
  string,
  {
    value: T
    display: string
    icon: string
  }
>

/**
 * Utility to generate mappings and options from a configuration
 */
function createOptionHelpers<T extends string>(config: OptionConfig<T>) {
  const options = Object.values(config).map(c => c.value)

  const displayMap = Object.fromEntries(
    Object.values(config).map(c => [c.value, c.display])
  )

  const iconMap = Object.fromEntries(
    Object.values(config).map(c => [c.value, c.icon])
  )

  const valueMap = Object.fromEntries(
    Object.entries(config).map(([key, c]) => [key, c.value])
  ) as Record<keyof typeof config, T>

  return {
    options,
    displayMap,
    iconMap,
    valueMap,
  }
}

// Font family options matching UI constraints
export const FontFamilyConfig: OptionConfig<string> = {
  SANS: {
    value: 'sans-serif',
    display: 'Sans Serif',
    icon: 'ph:text-aa-bold',
  },
  SERIF: {
    value: 'serif',
    display: 'Serif',
    icon: 'ph:text-t-bold',
  },
  MONO: {
    value: 'mono',
    display: 'monospace',
    icon: 'ph:text-code',
  },
}

// Corner style options matching UI constraints
export const CornerStyleConfig: OptionConfig<string> = {
  ROUNDED: {
    value: 'rounded',
    display: 'Rounded',
    icon: 'tabler:border-corner-rounded',
  },
  PILL: {
    value: 'pill',
    display: 'Pill Shape',
    icon: 'tabler:border-corner-pill',
  },
  SQUARE: {
    value: 'square',
    display: 'Square',
    icon: 'tabler:border-corner-square',
  },
}

// Generate helpers for FontFamily
const FontFamilyHelpers = createOptionHelpers(FontFamilyConfig)
export const FontFamily = FontFamilyHelpers.valueMap
export const fontOptions = FontFamilyHelpers.options
export const fontDisplayMap = FontFamilyHelpers.displayMap
export const fontIconMap = FontFamilyHelpers.iconMap

// Generate helpers for CornerStyle
const CornerStyleHelpers = createOptionHelpers(CornerStyleConfig)
export const CornerStyle = CornerStyleHelpers.valueMap
export const cornerStyleOptions = CornerStyleHelpers.options
export const cornerStyleDisplayMap = CornerStyleHelpers.displayMap
export const cornerStyleIconMap = CornerStyleHelpers.iconMap

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
  font_family: z.enum(Object.values(FontFamily)).optional(),
  corner_style: z.enum(Object.values(CornerStyle)).optional(),

  // Image related fields
  image_content_type: z.string().optional(),
  image_encoded: z.string().optional(),
  image_filename: z.string().optional(),
}).merge(baseNestedRecordSchema)

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
}).merge(baseNestedRecordSchema).strip()

// Export inferred types for use in stores/components
export type BrandSettings = z.infer<typeof brandSettingsInputSchema> & BaseNestedRecord
export type ImageProps = z.infer<typeof imagePropsSchema> & BaseNestedRecord
