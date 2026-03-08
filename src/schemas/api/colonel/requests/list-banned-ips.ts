// src/schemas/api/colonel/requests/list-banned-ips.ts
//
// Request schema for ColonelAPI::Logic::Colonel::ListBannedIPs
// GET /banned-ips
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const listBannedIPsRequestSchema = z.object({
  /** Page number */
  page: z.number().int().min(1).default(1),
  /** Items per page */
  per_page: z.number().int().min(1).max(100).default(50),
});

export type ListBannedIPsRequest = z.infer<typeof listBannedIPsRequestSchema>;
