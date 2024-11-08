// src/schemas/models/secret.ts
import { z } from 'zod'
import type { BaseApiRecord } from '@/types/api/responses'
import { baseApiRecordSchema, booleanFromString } from '@/utils/transforms'

/**
 * @fileoverview Secret schema for API transformation boundaries
 *
 * Key Design Decisions:
 * 1. Input schemas handle API -> App transformation
 * 2. App uses single shared type between stores/components
 * 3. No explicit output schemas - serialize when needed
 *
 * Validation Rules:
 * - Boolean fields come as strings from Ruby/Redis ('true'/'false')
 * - State field is validated against enum
 * - Optional fields explicitly marked
 */

// Secret state enum matching Ruby model
export const SecretState = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned'
} as const

/**
 * Base secret schema for shared fields
 */
const baseSecretSchema = baseApiRecordSchema.extend({
  share_domain: z.string(),
  original_size: z.number(),
  is_truncated: booleanFromString,
  verification: z.string()
})

/**
 * Schema for secret details view
 */
export const secretDetailsSchema = z.object({
  continue: z.boolean(),
  show_secret: z.boolean(),
  correct_passphrase: z.boolean(),
  display_lines: z.number(),
  one_liner: z.boolean()
})

export type SecretDetails = z.infer<typeof secretDetailsSchema>

/**
 * Schema for secret data from API
 */
export const secretDataSchema = baseSecretSchema.extend({
  key: z.string(),
  secret_key: z.string(),
  secret_shortkey: z.string(),
  is_owner: booleanFromString,
  has_passphrase: booleanFromString,
  secret_value: z.string(),
  secret: z.string().optional()
})

export type SecretData = z.infer<typeof secretDataSchema>

/**
 * Schema for full secret model
 */
export const secretSchema = baseSecretSchema.extend({
  custid: z.string(),
  state: z.enum([
    SecretState.NEW,
    SecretState.SHARED,
    SecretState.RECEIVED,
    SecretState.BURNED
  ]),
  value: z.string(),
  secret_value: z.string().optional(),
  metadata_key: z.string(),
  value_checksum: z.string(),
  value_encryption: z.string(),
  lifespan: z.number(),
  maxviews: z.literal(1) // Always 1 for backwards compatibility
})

export type Secret = z.infer<typeof secretSchema> & BaseApiRecord

/**
 * Schema for conceal data (combined secret and metadata)
 */
export const concealDetailsSchema = z.object({
  kind: z.string(),
  recipient: z.string(),
  recipient_safe: z.string()
})

export type ConcealDetails = z.infer<typeof concealDetailsSchema>
