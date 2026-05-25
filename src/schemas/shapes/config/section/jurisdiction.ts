// src/schemas/shapes/config/section/jurisdiction.ts

/**
 * Jurisdiction Configuration Shape
 *
 * Adds the identifier length bounds and `enabled` default on top of the
 * type-only jurisdiction contract.
 *
 * @see src/schemas/contracts/config/section/jurisdiction.ts
 */

import {
  jurisdictionSchema,
  jurisdictionIconSchema,
  regionSchema,
  regionsConfigSchema,
  jurisdictionDetailsSchema,
} from '@/schemas/contracts/config/section/jurisdiction';
import { augment } from '@/schemas/utils/augment';

export {
  jurisdictionSchema,
  jurisdictionIconSchema,
  regionSchema,
  regionsConfigSchema,
  jurisdictionDetailsSchema,
};

export type {
  Jurisdiction,
  JurisdictionIcon,
  Region,
  RegionsConfig,
  JurisdictionDetails,
} from '@/schemas/contracts/config/section/jurisdiction';

const jurisdictionIconShape = jurisdictionIconSchema;

const jurisdictionShape = augment(jurisdictionSchema, {
  identifier: (s) => s.min(2).max(24),
  enabled: (b) => b.default(true),
});

const regionShape = jurisdictionShape;

const regionsConfigShape = augment(regionsConfigSchema, {
  identifier: (s) => s.min(2).max(24),
});

const jurisdictionDetailsShape = jurisdictionDetailsSchema;

export {
  jurisdictionShape,
  jurisdictionIconShape,
  regionShape,
  regionsConfigShape,
  jurisdictionDetailsShape,
};
