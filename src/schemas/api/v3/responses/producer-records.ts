import { receiptBaseCanonical } from '@/schemas/contracts/receipt';
import { secretCanonical, secretDisplayTypeSchema } from '@/schemas/contracts/secret';
import { z } from 'zod';

// Current safe_dump projections, not tolerant model readers. Keep wire numbers
// and emitted aliases here; this does not decide their future deprecation.
export const secretStatusRecordSchema = secretCanonical.omit({ secret_value: true }).extend({
  display_type: secretDisplayTypeSchema,
  created: z.number(),
  updated: z.number(),
  is_viewed: z.boolean(),
  is_received: z.boolean(),
}).strict();

export const receiptSafeDumpRecordSchema = receiptBaseCanonical.omit({ custid: true }).extend({
  created: z.number(),
  updated: z.number(),
  shared: z.number().nullable(),
  previewed: z.number().nullable(),
  revealed: z.number().nullable(),
  burned: z.number().nullable(),
  recipients: z.array(z.string()).min(1).nullable(),
  show_recipients: z.boolean(),
  metadata_ttl: z.number(),
  // Legacy persisted aliases are emitted without the canonical timestamp casts.
  viewed: z.union([z.number(), z.string()]).nullable(),
  received: z.union([z.number(), z.string()]).nullable(),
  is_viewed: z.boolean(),
  is_received: z.boolean(),
}).required().strict();
