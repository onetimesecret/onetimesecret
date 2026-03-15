// src/schemas/api/v1/requests/create.ts
//
// Request schema for V1::Controllers::Index#create
// POST /create
//
//
// Alias for "share". V1 uses flat form params.

import { z } from 'zod';

export const createRequestSchema = z.object({
  /** The secret content */
  secret: z.string(),
  /** Time-to-live in seconds */
  ttl: z.number().int().optional(),
  /** Passphrase to protect the secret */
  passphrase: z.string().optional(),
  /** Recipient email address(es) */
  recipient: z.string().optional(),
  /** Custom domain for the share link */
  share_domain: z.string().optional(),
});

export type CreateRequest = z.infer<typeof createRequestSchema>;
