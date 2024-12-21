// src/schemas/models/domain/brand.ts
import { baseRecordSchema, type BaseRecord } from '@/schemas/models/base';
import { booleanFromString } from '@/utils/transforms';
import { z } from 'zod';

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
*/

type Option = {
  value: string;
  display: string;
  icon: string;
};

type OptionConfig = Record<string, Option>;

const createOptions = (config: OptionConfig) => {
  const options = Object.values(config).map((opt) => opt.value);
  const maps = Object.keys(config).reduce(
    (acc, key) => {
      const { value, display, icon } = config[key];
      acc.displayMap[value] = display;
      acc.iconMap[value] = icon;
      acc.valueMap[key] = value;
      return acc;
    },
    {
      displayMap: {} as Record<string, string>,
      iconMap: {} as Record<string, string>,
      valueMap: {} as Record<string, string>,
    }
  );
  return { options, ...maps };
};

const FontFamilyConfig: OptionConfig = {
  SANS: { value: 'sans', display: 'Sans Serif', icon: 'ph:text-aa-bold' },
  SERIF: { value: 'serif', display: 'Serif', icon: 'ph:text-t-bold' },
  MONO: { value: 'mono', display: 'Monospace', icon: 'ph:code' },
};

const CornerStyleConfig: OptionConfig = {
  ROUNDED: { value: 'rounded', display: 'Rounded', icon: 'tabler:border-corner-rounded' },
  PILL: { value: 'pill', display: 'Pill Shape', icon: 'tabler:border-corner-pill' },
  SQUARE: { value: 'square', display: 'Square', icon: 'tabler:border-corner-square' },
};

const {
  options: fontOptions,
  displayMap: fontDisplayMap,
  iconMap: fontIconMap,
  valueMap: FontFamily,
} = createOptions(FontFamilyConfig);

const {
  options: cornerStyleOptions,
  displayMap: cornerStyleDisplayMap,
  iconMap: cornerStyleIconMap,
  valueMap: CornerStyle,
} = createOptions(CornerStyleConfig);

export const brandSettingsInputSchema = z
  .object({
    primary_color: z.string().regex(/^#[0-9A-F]{6}$/i, 'Invalid hex color'),
    colour: z.string().optional(),
    instructions_pre_reveal: z.string().optional(),
    instructions_reveal: z.string().optional(),
    instructions_post_reveal: z.string().optional(),
    description: z.string().optional(),
    button_text_light: booleanFromString.default(false),
    allow_public_homepage: booleanFromString.default(false),
    allow_public_api: booleanFromString.default(false),
    font_family: z.enum(Object.values(FontFamily)).optional(),
    corner_style: z.enum(Object.values(CornerStyle)).optional(),
  })
  .merge(baseRecordSchema);

export const imagePropsSchema = z
  .object({
    encoded: z.string().optional(),
    content_type: z.string().optional(),
    filename: z.string().optional(),
    bytes: z.number().optional(),
    width: z.number().optional(),
    height: z.number().optional(),
    ratio: z.number().optional(),
  })
  .merge(baseRecordSchema)
  .strip();

export type BrandSettings = z.infer<typeof brandSettingsInputSchema> & BaseRecord;
export type ImageProps = z.infer<typeof imagePropsSchema> & BaseRecord;

export {
  CornerStyle,
  cornerStyleDisplayMap,
  cornerStyleIconMap,
  cornerStyleOptions,
  fontDisplayMap,
  FontFamily,
  fontIconMap,
  fontOptions,
};
