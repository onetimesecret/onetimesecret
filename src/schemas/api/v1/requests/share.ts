// src/schemas/api/v1/requests/share.ts
//
// Request schema for V1::Controllers::Index#share
// POST /share
//
//
// Alias for "create". V1 uses flat form params, not nested JSON.

import { z } from 'zod';

export const shareRequestSchema = z.object({
  /** The secret content to share */
  secret: z.string(),
  /** Time-to-live in seconds (default 7 days, min 1800, max 2592000) */
  ttl: z.number().int().optional(),
  /** Passphrase to protect the secret */
  passphrase: z.string().optional(),
  /** Recipient email address(es) */
  recipient: z.string().optional(),
  /** Custom domain for the share link */
  share_domain: z.string().optional(),
});

export type ShareRequest = z.infer<typeof shareRequestSchema>;
