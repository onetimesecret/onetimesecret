// Request body for PATCH /receipt/:identifier. Identifier is in the path.
import { z } from 'zod';

export const updateReceiptRequestSchema = z.object({
  /** Omit for no change; empty string clears. Ruby sanitizes and truncates to 500 characters. */
  memo: z.string().optional(),
});

export type UpdateReceiptRequest = z.infer<typeof updateReceiptRequestSchema>;
