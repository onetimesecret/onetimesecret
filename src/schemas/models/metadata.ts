// src/schemas/models/metadata.ts
import { baseApiRecordSchema } from '@/schemas/base';
import { secretInputSchema } from '@/schemas/models/secret';
import { booleanFromString, numberFromString } from '@/utils/transforms';
import { z } from 'zod';

/**
 * @fileoverview Metadata schema for API transformation boundaries
 *
 * Key Design Decisions:
 * 1. Input schemas handle API -> App transformation
 * 2. App uses single shared type between stores/components
 * 3. No explicit output schemas - serialize when needed
 *
 * Validation Rules:
 * - Boolean fields come as strings from Ruby/Redis ('true'/'false')
 * - Dates come as UTC strings or timestamps
 * - State field is validated against enum
 * - Optional fields explicitly marked
 */

// Metadata state enum matching Ruby model
export const MetadataState = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
} as const;

// Helper for converting Unix timestamps to Date objects
const unixTimestampToDate = (val: unknown) => {
  if (val instanceof Date) return val;
  if (typeof val === 'number') {
    // Convert seconds to milliseconds for Unix timestamps
    return new Date(val * 1000);
  }
  if (typeof val === 'string') {
    const num = Number(val);
    if (!isNaN(num)) {
      return new Date(num * 1000);
    }
    return new Date(val);
  }
  throw new Error('Invalid date value');
};

// Common base schema for all metadata records
const metadataCommonSchema = z.object({
  key: z.string(),
  shortkey: z.string(),
  secret_shortkey: z.string().optional(),
  recipients: z.array(z.string()).or(z.string()).optional(),
  share_domain: z.string().optional(),
  state: z.enum([
    MetadataState.NEW,
    MetadataState.SHARED,
    MetadataState.RECEIVED,
    MetadataState.BURNED,
    MetadataState.VIEWED,
  ]),
  created: z.union([z.string(), z.number(), z.date()]).transform(unixTimestampToDate),
  updated: z.union([z.string(), z.number(), z.date()]).transform(unixTimestampToDate),
});

// Base schema for list items
const metadataListItemBaseSchema = z.object({
  custid: z.string(),
  secret_ttl: z.union([z.string(), z.number()]).transform(Number),
  show_recipients: booleanFromString,
  is_received: booleanFromString,
  is_burned: booleanFromString,
  is_destroyed: booleanFromString,
  is_truncated: booleanFromString,
  identifier: z.string(),
});

// Schema for list items in the dashboard view
export const metadataListItemInputSchema = metadataCommonSchema.merge(metadataListItemBaseSchema);

// Schema for extended metadata fields (single record view)
const metadataExtendedBaseSchema = z.object({
  secret_key: z.string().optional(),
  created_date_utc: z.string(),
  expiration_stamp: z.string(),
  share_path: z.string(),
  burn_path: z.string(),
  metadata_path: z.string(),
  share_url: z.string(),
  metadata_url: z.string(),
  burn_url: z.string(),
  identifier: z.string(),
});

// Schema for full metadata record
export const metadataInputSchema = metadataCommonSchema.merge(metadataExtendedBaseSchema);

/**
 * Schema for metadata details
 */

// Schema for list view details
const metadataListItemDetailsBaseSchema = z.object({
  type: z.literal('list'),
  since: z.number(),
  now: z.union([z.string(), z.number(), z.date()]).transform(unixTimestampToDate),
  has_items: booleanFromString,
  received: z.array(metadataListItemInputSchema),
  notreceived: z.array(metadataListItemInputSchema),
});

export const metadataListItemDetailsInputSchema = metadataListItemDetailsBaseSchema;

// Schema for single record details
const metadataDetailsBaseSchema = z.object({
  type: z.literal('record'),
  title: z.string(),
  display_lines: numberFromString,
  display_feedback: booleanFromString,
  no_cache: booleanFromString,
  received_date: numberFromString,
  received_date_utc: numberFromString,
  burned_date: numberFromString,
  burned_date_utc: numberFromString,
  maxviews: numberFromString,
  has_maxviews: booleanFromString,
  view_count: numberFromString,
  has_passphrase: booleanFromString,
  can_decrypt: booleanFromString,
  secret_value: z.string().nullable().optional(),
  show_secret: booleanFromString,
  show_secret_link: booleanFromString,
  show_metadata_link: booleanFromString,
  show_metadata: booleanFromString,
  show_recipients: booleanFromString,
  is_destroyed: booleanFromString,
});

export const metadataDetailsInputSchema = metadataDetailsBaseSchema;

// Combined details schema for API responses with discriminated union
export const metadataDetailsSchema = z.discriminatedUnion('type', [
  metadataListItemDetailsInputSchema,
  metadataDetailsInputSchema,
]);

// Export types
export type Metadata = z.infer<typeof metadataInputSchema>;
export type MetadataDetails = z.infer<typeof metadataDetailsInputSchema>;
export type MetadataListItem = z.infer<typeof metadataListItemInputSchema>;
export type MetadataListItemDetails = z.infer<typeof metadataListItemDetailsInputSchema>;
export type MetadataDetailsUnion = z.infer<typeof metadataDetailsSchema>;

/**
 * Schema for combined secret and metadata (conceal data)
 */
const concealDataBaseSchema = z.object({
  metadata: metadataInputSchema,
  secret: secretInputSchema,
  share_domain: z.string(),
});

export const concealDataInputSchema = baseApiRecordSchema.merge(concealDataBaseSchema);

export type ConcealData = z.infer<typeof concealDataInputSchema>;

// Type guard to check if details are list details
export function isMetadataListItemDetails(
  details: MetadataDetailsUnion | null
): details is MetadataListItemDetails {
  return details !== null && details.type === 'list';
}

// Type guard to check if details are record details
export function isMetadataDetails(
  details: MetadataDetailsUnion | null
): details is MetadataDetails {
  return details !== null && details.type === 'record';
}
