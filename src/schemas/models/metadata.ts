import { createModelSchema } from '@/schemas/models/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * @fileoverview Metadata schema with unified transformations
 *
 * Key improvements:
 * 1. Unified transformation layer using base transforms
 * 2. Clearer type flow from API to frontend
 * 3. Maintained existing functionality
 *
 * Validation Rules:
 * - Boolean fields come as strings from Ruby/Redis ('true'/'false')
 * - Dates come as UTC strings or timestamps
 * - State field is validated against enum
 * - Optional fields explicitly marked
 */

/**
 * Metadata state enum matching Ruby model
 *
 * Using const object pattern over enum because:
 * 1. Produces simpler runtime code (just a plain object vs IIFE)
 * 2. Better tree-shaking since values can be inlined
 * 3. Works naturally with Zod's z.enum() which expects string literals
 * 4. More flexible for runtime operations (Object.keys(), etc.)
 * 5. Matches idiomatic TypeScript patterns for string-based enums
 */
export const MetadataState = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
  EXPIRED: 'expired',
  ORPHANED: 'orphaned',
} as const;

export type MetadataState = (typeof MetadataState)[keyof typeof MetadataState];

// Create a reusable schema for the state
export const metadataStateSchema = z.enum(Object.values(MetadataState) as [string, ...string[]]);

// Common base schema for all metadata records
export const metadataBaseSchema = createModelSchema({
  key: z.string(),
  shortid: z.string(),
  secret_shortid: z.string().optional(),
  recipients: z.array(z.string()).or(z.string()).nullable().optional(),
  share_domain: z.string().nullable().optional(),
  secret_ttl: transforms.fromString.number,
  metadata_ttl: transforms.fromString.number,
  lifespan: transforms.fromString.number,
  state: metadataStateSchema,
  created: transforms.fromString.date,
  updated: transforms.fromString.date,
  has_passphrase: z.boolean().optional(),
  shared: transforms.fromString.dateNullable.optional(),
  received: transforms.fromString.dateNullable.optional(),
  burned: transforms.fromString.dateNullable.optional(),
  viewed: transforms.fromString.dateNullable.optional(),
  // There is no "expired" time field as a time stamp that is set when the
  // metadata expires. We calculate expiration based on the lifespan (TTL).
  // of the secret.
  //
  // There is no "orphaned" time field. We use updated. To be orphaned is an
  // exceptional case and it's not something we specifically control. Unlike
  // burning or receiving which are linked to user actions, we don't know
  // when the metadata got into an orphaned state; only when we flagged it.
  is_viewed: transforms.fromString.boolean,
  is_received: transforms.fromString.boolean,
  is_burned: transforms.fromString.boolean,
  is_destroyed: transforms.fromString.boolean,
  is_expired: transforms.fromString.boolean,
  is_orphaned: transforms.fromString.boolean,
});

// Metadata shape in single record view
export const metadataSchema = metadataBaseSchema.merge(
  z.object({
    secret_identifier: z.string().nullish().optional(),
    secret_shortid: z.string().nullish().optional(),
    key: z.string().nullish().optional(),
    secret_state: metadataStateSchema.nullish().optional(),
    natural_expiration: z.string(),
    expiration: transforms.fromString.date,
    expiration_in_seconds: transforms.fromString.number,
    share_path: z.string(),
    burn_path: z.string(),
    metadata_path: z.string(),
    share_url: z.string(),
    metadata_url: z.string(),
    burn_url: z.string(),
    identifier: z.string(),
  })
);

// The details for each record in single record details
export const metadataDetailsSchema = z.object({
  type: z.literal('record'),
  display_lines: transforms.fromString.number,
  no_cache: transforms.fromString.boolean,
  secret_realttl: z.number().nullable().optional(),
  view_count: transforms.fromString.number.nullable(),
  has_passphrase: transforms.fromString.boolean,
  can_decrypt: transforms.fromString.boolean,
  secret_value: z.string().nullable().optional(),
  show_secret: transforms.fromString.boolean,
  show_secret_link: transforms.fromString.boolean,
  show_metadata_link: transforms.fromString.boolean,
  show_metadata: transforms.fromString.boolean,
  show_recipients: transforms.fromString.boolean,
  is_orphaned: transforms.fromString.boolean.nullable().optional(),
  is_expired: transforms.fromString.boolean.nullable().optional(),
});

// Export types
export type Metadata = z.infer<typeof metadataSchema>;
export type MetadataDetails = z.infer<typeof metadataDetailsSchema>;

export function isValidMetadataState(state: string): state is MetadataState {
  return Object.values(MetadataState).includes(state as MetadataState);
}

/**
 * CHANGELOG
 * ═══════════════════════
 *
 * [2025-03-03] FEATURE
 * ────────────────────────
 * Added new fields:
 * - secret_ttl: number
 * - metadata_ttl: number
 * - lifespan: number
 *
 * transform:
 *   All use transforms.fromString.number
 *
 * why: Added TTL and lifespan tracking to metadata records for consistent time-based operations
 */
