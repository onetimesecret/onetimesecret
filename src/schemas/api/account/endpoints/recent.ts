// src/schemas/api/account/endpoints/recent.ts

import { receiptBaseSchema } from '@/schemas/models';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Receipt shape in list view
// NOTE: Boolean state fields (is_viewed, is_received, etc.) come from receiptBaseSchema.
// These fields come from Receipt#safe_dump in the backend
// (lib/onetime/models/receipt/features/safe_dump_fields.rb)
export const receiptRecordsSchema = receiptBaseSchema.extend({
  custid: z.string().nullish(),
  owner_id: z.string().nullish(),
  // Override base schema's secret_ttl to handle both string and number from API
  secret_ttl: z.union([z.string(), z.number()]).transform(Number),
  show_recipients: transforms.fromString.boolean,
  identifier: z.string().nullish(),
  secret_identifier: z.string().nullish(),
  secret_shortid: z.string().nullish(),
  key: z.string().nullish(),
});

// The details for each record in list view
export const receiptRecordsDetailsSchema = z.object({
  type: z.string(), // literally the word "list"
  since: z.number(),
  now: transforms.fromString.date,
  has_items: transforms.fromString.boolean,
  received: z.array(receiptRecordsSchema),
  notreceived: z.array(receiptRecordsSchema),
});

export type ReceiptRecords = z.infer<typeof receiptRecordsSchema>;
export type ReceiptRecordsDetails = z.infer<typeof receiptRecordsDetailsSchema>;
