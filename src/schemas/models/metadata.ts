// src/schemas/models/metadata.ts
import { baseApiRecordSchema, type DetailsType } from '@/schemas/base';
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
 * - Dates come as UTC strings
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

/**
 * Schema for metadata data from API
 */

const metadataBaseSchema = z.object({
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
});

const metadataListItemBaseSchema = z.object({
  custid: z.string(),
  secret_ttl: z.string().transform(Number),
  show_recipients: booleanFromString,
  is_received: booleanFromString,
  is_burned: booleanFromString,
  is_destroyed: booleanFromString,
  is_truncated: booleanFromString,
});

export const metadataListItemInputSchema = baseApiRecordSchema
  .merge(metadataBaseSchema)
  .merge(metadataListItemBaseSchema)
  .strip();

const metadataListItemDetailsBaseSchema = z.object({
  since: z.number(),
  now: z.number(),
  has_items: booleanFromString,
  received: z.array(metadataListItemInputSchema),
  notreceived: z.array(metadataListItemInputSchema),
});

export const metadataListItemDetailsInputSchema = metadataListItemDetailsBaseSchema.strip();

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
});

export const metadataInputSchema = baseApiRecordSchema
  .merge(metadataBaseSchema)
  .merge(metadataExtendedBaseSchema)
  .strip();

/**
 * Schema for metadata details view
 * Handles string -> boolean transformations from API
 */
const metadataDetailsBaseSchema = z.object({
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
  secret_value: z.string(),
  show_secret: booleanFromString,
  show_secret_link: booleanFromString,
  show_metadata_link: booleanFromString,
  show_metadata: booleanFromString,
  show_recipients: booleanFromString,
});

export const metadataDetailsInputSchema = metadataDetailsBaseSchema.strip();

export type Metadata = z.infer<typeof metadataInputSchema>;
export type MetadataDetails = z.infer<typeof metadataDetailsInputSchema> & DetailsType;
export type MetadataListItem = z.infer<typeof metadataListItemInputSchema>;
export type MetadataListItemDetails = z.infer<typeof metadataListItemDetailsInputSchema>;

/**
 * Schema for combined secret and metadata (conceal data)
 */
const concealDataBaseSchema = z.object({
  metadata: metadataInputSchema,
  secret: secretInputSchema,
  share_domain: z.string(),
});

export const concealDataInputSchema = baseApiRecordSchema.merge(concealDataBaseSchema).strip();

export type ConcealData = z.infer<typeof concealDataInputSchema>;
