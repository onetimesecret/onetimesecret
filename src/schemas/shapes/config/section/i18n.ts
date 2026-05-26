// src/schemas/shapes/config/section/i18n.ts

/**
 * Internationalization Configuration Shape
 *
 * Adds runtime defaults on top of the type-only i18n contract.
 *
 * @see src/schemas/contracts/config/section/i18n.ts
 */

import { i18nSchema } from '@/schemas/contracts/config/section/i18n';
import { augment } from '@/schemas/utils/augment';

export { i18nSchema };

const i18nShape = augment(i18nSchema, {
  enabled: (b) => b.default(false),
  default_locale: (s) => s.default('en'),
  locales: (a) => a.default([]),
  incomplete: (a) => a.default([]),
  date_format: (s) => s.default('locale'),
  datetime_format: (s) => s.default('locale'),
});

export { i18nShape };
