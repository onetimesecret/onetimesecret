// src/schemas/api/incoming/responses/incoming-secret.ts

import { z } from 'zod';

/**
 * Schema for receipt record in the response
 * Note: Many fields can be null or absent from the API via safe_dump.
 * Use .nullish() to accept null, undefined, and missing fields.
 * Fix for #2500: state was previously z.string() which rejected null.
 */
const receiptRecordSchema = z.object({
  identifier: z.string(),
  key: z.string(),
  custid: z.string().nullish(),
  owner_id: z.string().nullish(),
  state: z.string().nullish(),
  secret_shortid: z.string().nullish(),
  shortid: z.string().nullish(),
  memo: z.string().nullish(),
  recipients: z.string().nullish(),
  // Additional fields from actual API response
  secret_ttl: z.number().nullish(),
  receipt_ttl: z.number().nullish(),
  lifespan: z.number().nullish(),
  share_domain: z.string().nullish(),
  created: z.number().nullish(),
  updated: z.number().nullish(),
  shared: z.number().nullish(),
  received: z.number().nullish(),
  burned: z.number().nullish(),
  viewed: z.number().nullish(),
  show_recipients: z.boolean().nullish(),
  is_viewed: z.boolean().nullish(),
  is_received: z.boolean().nullish(),
  is_burned: z.boolean().nullish(),
  is_expired: z.boolean().nullish(),
  is_orphaned: z.boolean().nullish(),
  is_destroyed: z.boolean().nullish(),
  has_passphrase: z.boolean().nullish(),
});

/**
 * Schema for secret object in the response
 * Fix for #2500: state was previously z.string() which rejected null.
 */
const secretRecordSchema = z.object({
  identifier: z.string(),
  key: z.string(),
  state: z.string().nullish(),
  shortid: z.string().nullish(),
  // Additional fields from actual API response
  secret_ttl: z.number().nullish(),
  lifespan: z.number().nullish(),
  has_passphrase: z.boolean().nullish(),
  verification: z.boolean().nullish(),
  created: z.number().nullish(),
  updated: z.number().nullish(),
});

/**
 * Schema for incoming secret creation response
 * Matches the actual V3 API response format
 *
 * Note: V3 API uses modern "receipt" terminology exclusively.
 */
export const incomingSecretResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().nullish(),
  shrimp: z.string().nullish(),
  custid: z.string().nullish(),
  record: z.object({
    receipt: receiptRecordSchema,
    secret: secretRecordSchema,
  }),
  details: z
    .object({
      memo: z.string().nullish(),
      recipient: z.string().nullish(),
    })
    .nullish(),
});

export type IncomingSecretResponse = z.infer<typeof incomingSecretResponseSchema>;
