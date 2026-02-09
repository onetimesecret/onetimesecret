// src/schemas/i18n/locale.ts

import { z } from 'zod';

/**
 * Validates BCP 47 language tags:
 * - 2-letter language code (en, fr)
 * - Language + region with separator (en_CA, pt-BR, DE-at, eo)
 * Case insensitive.
 */
export const localeCodeSchema = z
  .string()
  .min(2)
  .max(5)
  .regex(/^[a-z]{2}(?:[_-][a-z]{2})?$/i, 'Invalid locale format');

export type Locale = z.infer<typeof localeCodeSchema>;

/**
 * Schema for a single entry in locales/content/{locale}/*.json files.
 *
 * Each key maps to an object with text content, a content hash for
 * change detection, and an optional renderer hint.
 *
 * Renderer indicates which template engine consumes the entry:
 * - "vue" (default): Vue i18n / ICU MessageFormat. Interpolation: {variable}
 * - "erb": Ruby I18n via ERB templates. Interpolation: %{variable}
 *
 * Only email.json entries use "erb". All other locale files default to
 * "vue" and omit this field. Scripts and linters should treat absent
 * renderer as "vue".
 */
export const localeContentEntrySchema = z.object({
  text: z.string(),
  sha256: z.string().optional(),
  renderer: z.enum(['vue', 'erb']).default('vue'),
});

export type LocaleContentEntry = z.infer<typeof localeContentEntrySchema>;

/**
 * Input type for localeContentEntrySchema (before defaults are applied).
 * Use this when typing raw JSON data before Zod parsing.
 */
export type LocaleContentEntryInput = z.input<typeof localeContentEntrySchema>;
