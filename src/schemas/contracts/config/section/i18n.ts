// src/schemas/contracts/config/section/i18n.ts

/**
 * Internationalization Configuration Schema
 *
 * Maps to the `internationalization:` section in config.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults belong in `shapes/config/section/i18n.ts`.
 */

import { z } from 'zod';

/**
 * i18n configuration schema
 */
const i18nSchema = z.object({
  enabled: z.boolean().optional(),
  default_locale: z.string().optional(),
  fallback_locale: z.record(z.string(), z.union([z.array(z.string()), z.string()])),
  locales: z.array(z.string()).optional(),
  incomplete: z.array(z.string()).optional(),
  date_format: z.string().optional(),
  datetime_format: z.string().optional(),
});

export { i18nSchema };
