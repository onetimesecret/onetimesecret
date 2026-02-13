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
 * Source locale entry (e.g., en/00-common.json).
 * content_hash is the SHA-256 prefix of this entry's own text,
 * recomputed whenever the source text changes.
 */
export const sourceLocaleEntrySchema = z.object({
  text: z.string(),
  content_hash: z.string().length(8).optional(),
  renderer: z.enum(['vue', 'erb']).default('vue'),
});

export type SourceLocaleEntry = z.infer<typeof sourceLocaleEntrySchema>;

/**
 * Translation locale entry (e.g., fr_FR/00-common.json).
 * source_hash is the content_hash of the source locale entry
 * at the time this translation was created or last updated.
 * Staleness check: source_hash !== current source content_hash.
 */
export const translationLocaleEntrySchema = z.object({
  text: z.string(),
  source_hash: z.string().length(8).optional(),
  renderer: z.enum(['vue', 'erb']).default('vue'),
});

export type TranslationLocaleEntry = z.infer<typeof translationLocaleEntrySchema>;

/**
 * Schema for a single entry in locales/content/{locale}/*.json files.
 *
 * Accepts both content_hash (source locales) and source_hash (translations).
 * Use this when the locale context is unknown, e.g. in generic tooling
 * that processes all locale files uniformly.
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
  content_hash: z.string().length(8).optional(),
  source_hash: z.string().length(8).optional(),
  renderer: z.enum(['vue', 'erb']).default('vue'),
});

export type LocaleContentEntry = z.infer<typeof localeContentEntrySchema>;

/**
 * Input type for localeContentEntrySchema (before defaults are applied).
 * Use this when typing raw JSON data before Zod parsing.
 */
export type LocaleContentEntryInput = z.input<typeof localeContentEntrySchema>;

/**
 * Complete locale file: flat key -> entry mapping.
 */
export const localeFileSchema = z.record(z.string(), localeContentEntrySchema);

export type LocaleFile = z.infer<typeof localeFileSchema>;
