// Query parameters for GET /receipt/recent; this operation has no body.
import { z } from 'zod';

export const listReceiptsRequestSchema = z.object({
  scope: z
    .string()
    .optional()
    .describe(
      'Omit for personal receipts. Use org or domain for scoped receipts, subject to existing authorization. Other scalar values currently fall back to the personal list.'
    ),
  domain_extid: z
    .string()
    .optional()
    .describe('Required when scope=domain; the domain must be accessible to the caller.'),
});

export type ListReceiptsRequest = z.infer<typeof listReceiptsRequestSchema>;
