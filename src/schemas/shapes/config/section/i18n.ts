// src/schemas/shapes/config/section/i18n.ts

/**
 * Internationalization Configuration Shape
 *
 * Adds runtime defaults on top of the type-only i18n contract.
 *
 * @see src/schemas/contracts/config/section/i18n.ts
 */

import { z } from 'zod';

export { i18nSchema } from '@/schemas/contracts/config/section/i18n';

const i18nShape = z.object({
  enabled: z.boolean().default(false),
  default_locale: z.string().default('en'),
  fallback_locale: z.record(z.string(), z.union([z.array(z.string()), z.string()])),
  locales: z.array(z.string()).default([]),
  incomplete: z.array(z.string()).default([]),
  date_format: z.string().default('locale'),
  datetime_format: z.string().default('locale'),
});

export { i18nShape };
