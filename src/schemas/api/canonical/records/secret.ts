// src/schemas/api/canonical/records/secret.ts
//
// Canonical secret record schema — field names and output types only.
// Version-specific schemas (V2, V3) extend this with wire-format transforms.
//
// This schema owns the field contract. V2/V3 own the encoding.

import { z } from 'zod';

/**
 * Secret state values.
 *
 * STATE TERMINOLOGY MIGRATION:
 *   'viewed'   -> 'previewed'  (link accessed, confirmation shown)
 *   'received' -> 'revealed'   (secret content decrypted/consumed)
 *
 * API sends BOTH old and new values for backward compatibility.
 */
export const secretStateValues = [
  'new',
  'received',   // @deprecated — use 'revealed'
  'revealed',
  'burned',
  'viewed',     // @deprecated — use 'previewed'
  'previewed',
] as const;

export type SecretState = (typeof secretStateValues)[number];

/**
 * Secret state enum object.
 *
 * Using const object pattern over enum because:
 * 1. Produces simpler runtime code (just a plain object vs IIFE)
 * 2. Better tree-shaking since values can be inlined
 * 3. Works naturally with Zod's z.enum()
 *
 * STATE TERMINOLOGY MIGRATION:
 *   'viewed'   -> 'previewed'  (link accessed, confirmation shown)
 *   'received' -> 'revealed'   (secret content decrypted/consumed)
 *
 * API sends BOTH old and new values for backward compatibility.
 * @deprecated VIEWED and RECEIVED — use PREVIEWED and REVEALED instead
 */
export const SecretState = {
  NEW: 'new',
  RECEIVED: 'received',
  REVEALED: 'revealed',
  BURNED: 'burned',
  VIEWED: 'viewed',
  PREVIEWED: 'previewed',
} as const;

export const secretStateSchema = z.enum(secretStateValues);

/**
 * Type guard for secret state validation.
 */
export function isValidSecretState(state: string): state is SecretState {
  return secretStateValues.includes(state as SecretState);
}

/**
 * Canonical secret base record.
 *
 * Defines field names and output types (post-parse).
 * No transforms — those are version-specific.
 */
export const secretBaseCanonical = z.object({
  identifier: z.string(),
  key: z.string(),
  shortid: z.string(),
  state: secretStateSchema,
  has_passphrase: z.boolean(),
  verification: z.boolean(),
  secret_value: z.string().optional(),
});

/**
 * Canonical full secret record (includes TTL fields).
 */
export const secretCanonical = secretBaseCanonical.extend({
  secret_ttl: z.number(),
  lifespan: z.number(),
});

/**
 * Canonical secret record with timestamps (V3 wire format includes these).
 * V2 can omit created/updated when deriving.
 */
export const secretWithTimestampsCanonical = secretCanonical.extend({
  created: z.date(),
  updated: z.date(),
});

/**
 * Canonical secret details (metadata alongside the record).
 */
export const secretDetailsCanonical = z.object({
  continue: z.boolean(),
  is_owner: z.boolean(),
  show_secret: z.boolean(),
  correct_passphrase: z.boolean(),
  display_lines: z.number(),
  one_liner: z.boolean().nullable(),
});

// Type exports
export type SecretBaseCanonical = z.infer<typeof secretBaseCanonical>;
export type SecretCanonical = z.infer<typeof secretCanonical>;
export type SecretWithTimestampsCanonical = z.infer<typeof secretWithTimestampsCanonical>;
export type SecretDetailsCanonical = z.infer<typeof secretDetailsCanonical>;
