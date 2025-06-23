// src/schemas/config/i18n.ts

import { z } from 'zod/v4';
import { nullableString } from './shared/primitives';

const sectionI18nSchema = z.object({
  enabled: z.boolean().default(false),
  default_locale: z.string().default('en'),
  fallback_locale: z.record(z.string(), z.union([z.array(z.string()), z.string()])),
  locales: z.array(z.string()).default([]),
  incomplete: z.array(z.string()).default([]),
});
