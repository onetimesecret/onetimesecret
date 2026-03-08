// src/schemas/api/colonel/requests/ban-ip.ts
//
// Request schema for ColonelAPI::Logic::Colonel::BanIP
// POST /banned-ips
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const banIPRequestSchema = z.object({
  /** IP address or CIDR range to ban */
  ip_address: z.string(),
  /** Reason for ban (max 255 chars) */
  reason: z.string().optional(),
  /** Expiration timestamp (omit for permanent) */
  expiration: z.number().int().optional(),
});

export type BanIPRequest = z.infer<typeof banIPRequestSchema>;
