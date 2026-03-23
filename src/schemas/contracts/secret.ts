// src/schemas/contracts/secret.ts
// @see src/tests/stores/secrets/secretStoreFieldHandling.spec.ts - Test fixtures
//
// Canonical secret record schema — field names and output types only.
// Version-specific schemas (V2, V3) extend this with wire-format transforms.
//
// This schema owns the field contract. V2/V3 own the encoding.

/**
 * Secret record contracts defining field names and output types.
 *
 * These canonical schemas define the "what" (field names and final types)
 * without the "how" (wire-format transforms). Version-specific shapes
 * in `shapes/v2/secret.ts` and `shapes/v3/secret.ts` extend these with
 * appropriate transforms for each API version.
 *
 * @module contracts/secret
 * @category Contracts
 * @see {@link "shapes/v2/secret"} - V2 wire format with string transforms
 * @see {@link "shapes/v3/secret"} - V3 wire format with number-to-Date transforms
 */

import { z } from 'zod';

/**
 * Secret state values as a const tuple.
 *
 * Contracts represent canonical fields only. Shapes own backward-compat
 * aliases (viewed, received) as wire-format concerns.
 *
 * @category Contracts
 * @example
 * ```typescript
 * // Use with Zod enum
 * const stateSchema = z.enum(secretStateValues);
 *
 * // Type narrowing
 * if (secretStateValues.includes(value as SecretState)) {
 *   // value is SecretState
 * }
 * ```
 */
export const secretStateValues = [
  'new',
  'revealed',
  'burned',
  'previewed',
] as const;

export type SecretState = (typeof secretStateValues)[number];

/**
 * Secret state enum object for runtime state checks.
 *
 * Using const object pattern over enum because:
 * 1. Produces simpler runtime code (just a plain object vs IIFE)
 * 2. Better tree-shaking since values can be inlined
 * 3. Works naturally with Zod's z.enum()
 *
 * Contracts represent canonical fields only. V2 shapes extend this
 * with deprecated aliases (VIEWED, RECEIVED) for backward compatibility.
 *
 * @category Contracts
 * @example
 * ```typescript
 * if (secret.state === SecretState.REVEALED) {
 *   // Secret has been revealed
 * }
 *
 * // Use in switch statements
 * switch (secret.state) {
 *   case SecretState.NEW:
 *     return 'Pending';
 *   case SecretState.REVEALED:
 *     return 'Viewed';
 *   case SecretState.BURNED:
 *     return 'Destroyed';
 * }
 * ```
 */
export const SecretState = {
  NEW: 'new',
  REVEALED: 'revealed',
  BURNED: 'burned',
  PREVIEWED: 'previewed',
} as const;

/**
 * Zod schema for validating secret state values.
 *
 * @category Contracts
 */
export const secretStateSchema = z.enum(secretStateValues);

/**
 * Type guard for runtime secret state validation.
 *
 * @param state - String to validate
 * @returns True if state is a valid SecretState value
 *
 * @category Contracts
 * @example
 * ```typescript
 * const userInput = 'revealed';
 * if (isValidSecretState(userInput)) {
 *   // userInput is now typed as SecretState
 *   console.log(`Valid state: ${userInput}`);
 * }
 * ```
 */
export function isValidSecretState(state: string): state is SecretState {
  return secretStateValues.includes(state as SecretState);
}

/**
 * Canonical secret base record contract.
 *
 * Defines field names and output types (post-parse).
 * No transforms - those are version-specific in shapes.
 *
 * @category Contracts
 * @see {@link "shapes/v2/secret".secretSchema} - V2 wire format
 * @see {@link "shapes/v3/secret".secretSchema} - V3 wire format
 *
 * @example
 * ```typescript
 * // Extend in version-specific shapes
 * const secretBaseV2 = secretBaseCanonical.extend({
 *   has_passphrase: transforms.fromString.boolean,
 * });
 *
 * // Derive TypeScript type
 * type SecretBase = z.infer<typeof secretBaseCanonical>;
 * ```
 */
export const secretBaseCanonical = z.object({
  identifier: z.string(),
  key: z.string(),
  shortid: z.string(),
  state: secretStateSchema,
  has_passphrase: z.boolean(),
  verification: z.boolean(),
  secret_value: z.string().optional(),

  // State boolean fields (canonical only)
  is_previewed: z.boolean(),
  is_revealed: z.boolean(),
});

/**
 * Canonical full secret record with TTL fields.
 *
 * Extends base record with time-to-live and lifespan fields.
 *
 * @category Contracts
 * @see {@link secretBaseCanonical} - Base record without TTL
 *
 * @example
 * ```typescript
 * const secret = secretCanonical.parse(apiResponse);
 * console.log(`Expires in ${secret.secret_ttl} seconds`);
 * ```
 */
export const secretCanonical = secretBaseCanonical.extend({
  secret_ttl: z.number(),
  lifespan: z.number(),
});

/**
 * Canonical secret record with timestamps.
 *
 * V3 wire format includes created/updated as Unix timestamps.
 * V2 shapes can omit these fields when deriving.
 *
 * @category Contracts
 * @see {@link secretCanonical} - Without timestamps
 *
 * @example
 * ```typescript
 * const secret = secretWithTimestampsCanonical.parse(v3Response);
 * console.log(`Created: ${secret.created.toISOString()}`);
 * ```
 */
export const secretWithTimestampsCanonical = secretCanonical.extend({
  created: z.date(),
  updated: z.date(),
});

/**
 * Canonical secret details contract.
 *
 * Metadata returned alongside secret records for display logic.
 *
 * @category Contracts
 * @see {@link "shapes/v2/secret".secretDetailsSchema} - V2 wire format
 *
 * @example
 * ```typescript
 * const details = secretDetailsCanonical.parse(apiResponse.details);
 * if (details.show_secret && details.correct_passphrase) {
 *   // Display the secret content
 * }
 * ```
 */
export const secretDetailsCanonical = z.object({
  continue: z.boolean(),
  is_owner: z.boolean(),
  show_secret: z.boolean(),
  correct_passphrase: z.boolean(),
  display_lines: z.number(),
  one_liner: z.boolean().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for base secret record (without TTL or timestamps). */
export type SecretBaseCanonical = z.infer<typeof secretBaseCanonical>;

/** TypeScript type for full secret record with TTL fields. */
export type SecretCanonical = z.infer<typeof secretCanonical>;

/** TypeScript type for secret record with timestamps. */
export type SecretWithTimestampsCanonical = z.infer<typeof secretWithTimestampsCanonical>;

/** TypeScript type for secret details metadata. */
export type SecretDetailsCanonical = z.infer<typeof secretDetailsCanonical>;
