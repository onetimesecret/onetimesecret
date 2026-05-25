// src/schemas/shapes/config/section/jurisdiction.ts

/**
 * Jurisdiction Configuration Shape
 *
 * Adds runtime defaults and value constraints on top of the type-only
 * jurisdiction contract — identifier length bounds and the enabled default.
 *
 * @see src/schemas/contracts/config/section/jurisdiction.ts
 */

import { z } from 'zod';

export {
  jurisdictionSchema,
  jurisdictionIconSchema,
  regionSchema,
  regionsConfigSchema,
  jurisdictionDetailsSchema,
} from '@/schemas/contracts/config/section/jurisdiction';

export type {
  Jurisdiction,
  JurisdictionIcon,
  Region,
  RegionsConfig,
  JurisdictionDetails,
} from '@/schemas/contracts/config/section/jurisdiction';

const jurisdictionIconShape = z.object({
  collection: z.string(),
  name: z.string(),
});

const jurisdictionShape = z.object({
  identifier: z.string().min(2).max(24),
  display_name_i18n_key: z.string(),
  domain: z.string(),
  icon: jurisdictionIconShape.optional(),
  enabled: z.boolean().default(true),
});

const regionShape = jurisdictionShape;

const regionsConfigShape = z.object({
  identifier: z.string().min(2).max(24),
  enabled: z.boolean(),
  current_jurisdiction: z.string(),
  jurisdictions: z.array(jurisdictionShape),
});

const jurisdictionDetailsShape = z.object({
  is_default: z.boolean(),
  is_current: z.boolean(),
});

export {
  jurisdictionShape,
  jurisdictionIconShape,
  regionShape,
  regionsConfigShape,
  jurisdictionDetailsShape,
};
