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
  secretStateValues as canonicalStateValues,
  SecretState as CanonicalSecretState,
} from '@/schemas/contracts';
import { createModelSchema } from '@/schemas/shapes/v2/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V2 state values (includes deprecated aliases for backward compatibility)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 secret state values — extends canonical with deprecated aliases.
 */
export const secretStateValues = [
  ...canonicalStateValues,
  'received', // @deprecated — use 'revealed'
  'viewed', // @deprecated — use 'previewed'
] as const;

export type SecretState = (typeof secretStateValues)[number];

/**
 * V2 secret state enum object — extends canonical with deprecated aliases.
 */
export const SecretState = {
  ...CanonicalSecretState,
  RECEIVED: 'received', // @deprecated — use REVEALED
  VIEWED: 'viewed', // @deprecated — use PREVIEWED
} as const;

export const secretStateSchema = z.enum(secretStateValues);

/**
 * Type guard for V2 secret state validation (includes deprecated values).
 */
export function isValidSecretState(state: string): state is SecretState {
  return secretStateValues.includes(state as SecretState);
}

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
  is_previewed: transforms.fromString.boolean,
  is_revealed: transforms.fromString.boolean,
};

/**
 * Deprecated boolean field overrides for backward compatibility.
 */
const v2DeprecatedBooleanOverrides = {
  is_viewed: transforms.fromString.boolean, // @deprecated — use is_previewed
  is_received: transforms.fromString.boolean, // @deprecated — use is_revealed
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
const secretBaseSchema = secretBaseCanonical.extend({
  ...v2StringOverrides,
  ...v2DeprecatedBooleanOverrides,
});

// List view schema (stripped down version)
export const secretResponsesSchema = createModelSchema(secretBaseSchema.shape).strip();

// Full secret schema with TTL fields
export const secretSchema = createModelSchema({
  ...secretCanonical.extend({
    ...v2StringOverrides,
    ...v2DeprecatedBooleanOverrides,
  }).shape,
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
