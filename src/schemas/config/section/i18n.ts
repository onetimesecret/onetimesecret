// src/schemas/config/section/i18n.ts

/**
 * Internationalization Configuration Schema
 *
 * Maps to the `internationalization:` section in config.defaults.yaml
 */

import { z } from 'zod';

/**
 * i18n configuration schema
 */
const i18nSchema = z.object({
  enabled: z.boolean().default(false),
  default_locale: z.string().default('en'),
  fallback_locale: z.record(z.string(), z.union([z.array(z.string()), z.string()])),
  locales: z.array(z.string()).default([]),
  incomplete: z.array(z.string()).default([]),
});

export { i18nSchema };
