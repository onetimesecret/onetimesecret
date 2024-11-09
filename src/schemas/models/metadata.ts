// src/schemas/models/metadata.ts

import { baseApiRecordSchema, type BaseApiRecord } from '@/schemas/base';
import { type DetailsType } from '@/schemas/base'
import { booleanFromString } from '@/utils/transforms';
import { z } from 'zod';

import { secretInputSchema } from './secret';


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
  BURNED: 'burned'
} as const

/**
 * Schema for metadata data from API
 */

export const metadataDataSchema = baseApiRecordSchema.extend({
  key: z.string(),
  shortkey: z.string(),
  secret_key: z.string(),
  secret_shortkey: z.string(),
  recipients: z.array(z.string()),
  created_date_utc: z.string(),
  expiration_stamp: z.string(),
  share_path: z.string(),
  burn_path: z.string(),
  metadata_path: z.string(),
  share_url: z.string(),
  metadata_url: z.string(),
  burn_url: z.string(),
  share_domain: z.string()
})

export type MetadataData = z.infer<typeof metadataDataSchema>

/**
 * Schema for metadata details view
 * Handles string -> boolean transformations from API
 */
export const metadataDetailsSchema = z.object({
  body_class: z.string(),
  burned_date_utc: z.string(),
  burned_date: z.string(),
  can_decrypt: booleanFromString,
  display_feedback: booleanFromString,
  display_lines: z.number(),
  has_maxviews: booleanFromString,
  has_passphrase: booleanFromString,
  is_burned: booleanFromString,
  is_destroyed: booleanFromString,
  is_received: booleanFromString,
  maxviews: z.number(),
  no_cache: booleanFromString,
  received_date_utc: z.string(),
  received_date: z.string(),
  secret_value: z.string(),
  show_metadata_link: booleanFromString,
  show_metadata: booleanFromString,
  show_recipients: booleanFromString,
  show_secret_link: booleanFromString,
  show_secret: booleanFromString,
  title: z.string(),
  is_truncated: booleanFromString,
  view_count: z.number()
}).passthrough()

export type MetadataDetails = z.infer<typeof metadataDetailsSchema> & DetailsType

/**
 * Schema for dashboard metadata extensions
 */
export const dashboardMetadataSchema = baseApiRecordSchema.extend({
  shortkey: z.string(),
  show_recipients: booleanFromString,
  stamp: z.string(),
  uri: z.string(),
  is_received: booleanFromString,
  is_burned: booleanFromString,
  is_destroyed: booleanFromString
})

export type DashboardMetadata = z.infer<typeof dashboardMetadataSchema>

/**
 * Schema for full metadata model
 */
export const metadataSchema = dashboardMetadataSchema.extend({
  custid: z.string(),
  state: z.enum([
    MetadataState.NEW,
    MetadataState.SHARED,
    MetadataState.RECEIVED,
    MetadataState.BURNED
  ]),
  secret_key: z.string(),
  secret_shortkey: z.string(),
  secret_ttl: z.number(),
  share_domain: z.string(),
  passphrase: z.string(),
  viewed: booleanFromString,
  received: booleanFromString,
  shared: booleanFromString,
  burned: booleanFromString,
  recipients: z.array(z.string()),
  truncate: booleanFromString,
  key: z.string()
})

export type Metadata = z.infer<typeof metadataSchema> & BaseApiRecord

/**
 * Schema for combined secret and metadata (conceal data)
 */
export const concealDataSchema = baseApiRecordSchema.extend({
  metadata: metadataDataSchema,
  secret: secretInputSchema,
  share_domain: z.string()
})

export type ConcealData = z.infer<typeof concealDataSchema>
