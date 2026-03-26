// src/schemas/api/v1/requests/generate.ts
//
// Request schema for V1::Controllers::Index#generate
// POST /generate
//
//
// V1 generate — server creates the secret value. Flat form params.

import { z } from 'zod';

export const generateRequestSchema = z.object({
  /** Time-to-live in seconds */
  ttl: z.number().int().optional(),
  /** Passphrase to protect the secret */
  passphrase: z.string().optional(),
  /** Recipient email address(es) */
  recipient: z.string().optional(),
  /** Custom domain for the share link */
  share_domain: z.string().optional(),
});

export type GenerateRequest = z.infer<typeof generateRequestSchema>;
