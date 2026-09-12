// src/schemas/i18n/locale.ts

import { z } from 'zod';

/**
 * Upper bound for a locale tag. RFC 5646 recommends sizing buffers for
 * language tags at 35 characters, which covers every registered tag plus
 * script/region/variant combinations browsers actually send.
 */
const MAX_LOCALE_LENGTH = 35;

/**
 * Whether the tag is structurally well-formed BCP 47 (#4284).
 *
 * Delegates to Intl.getCanonicalLocales instead of a hand-rolled regex so
 * that real-world tags like en-US-POSIX, zh-Hant-TW, and es-419 validate.
 * Grammar-valid but unassigned tags also pass; that is fine because every
 * consumer still gates on the supported-locales list before use.
 * Case is irrelevant (canonicalization normalizes it), and underscores are
 * treated as hyphens since server-side locales use the it_IT form.
 */
function isWellFormedLocale(tag: string): boolean {
  try {
    return Intl.getCanonicalLocales(tag.replace(/_/g, '-')).length > 0;
  } catch {
    return false;
  }
}

/**
 * Validates BCP 47 language tags:
 * - language code (en, fr, eo)
 * - language + region with separator (en_CA, pt-BR, DE-at, es-419)
 * - language + script and/or variants (zh-Hant-TW, en-US-POSIX)
 * Case insensitive; accepts both hyphen and underscore separators.
 */
export const localeCodeSchema = z
  .string()
  .min(2)
  .max(MAX_LOCALE_LENGTH)
  .refine(isWellFormedLocale, 'Invalid locale format');

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
