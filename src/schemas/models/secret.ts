// src/schemas/models/secret.ts
//
// V2 wire-format schemas for secrets.
// Derives from canonical schemas, adding V2-specific string transforms.
//
// V2 API sends data as Redis-serialized strings; these transforms convert
// to the correct output types.

import {
  secretBaseCanonical,
  secretCanonical,
  secretDetailsCanonical,
  secretStateSchema,
  secretStateValues,
  SecretState,
  isValidSecretState,
} from '@/schemas/api/canonical/records';
import { createModelSchema } from '@/schemas/models/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Re-export from canonical
export { SecretState, secretStateSchema, secretStateValues, isValidSecretState };

// ─────────────────────────────────────────────────────────────────────────────
// V2 string transform overrides
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 wire format overrides.
 * V2 sends booleans/numbers as strings from Redis.
 */
const v2StringOverrides = {
  has_passphrase: transforms.fromString.boolean,
  verification: transforms.fromString.boolean,
};

// ─────────────────────────────────────────────────────────────────────────────
// Record schemas (V2 wire format: canonical + string transforms)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 secret base schema.
 *
 * Derives from canonical, adds V2 string transforms.
 * Uses createModelSchema to add identifier, created, updated from base.
 */
const secretBaseSchema = secretBaseCanonical.extend(v2StringOverrides);

// List view schema (stripped down version)
export const secretResponsesSchema = createModelSchema(secretBaseSchema.shape).strip();

// Full secret schema with TTL fields
export const secretSchema = createModelSchema({
  ...secretCanonical.extend(v2StringOverrides).shape,
  secret_ttl: transforms.fromString.number,
  lifespan: transforms.fromString.number,
}).strip();

/**
 * V2 secret details.
 *
 * Derives from canonical, adds V2 string transforms.
 */
export const secretDetailsSchema = secretDetailsCanonical.extend({
  continue: transforms.fromString.boolean,
  is_owner: transforms.fromString.boolean,
  show_secret: transforms.fromString.boolean,
  correct_passphrase: transforms.fromString.boolean,
  display_lines: transforms.fromString.number,
  one_liner: transforms.fromString.boolean.nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type Secret = z.infer<typeof secretSchema>;
export type SecretDetails = z.infer<typeof secretDetailsSchema>;
export type SecretList = z.infer<typeof secretResponsesSchema>;
