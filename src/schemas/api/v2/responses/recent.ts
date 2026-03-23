// src/schemas/api/v2/responses/recent.ts
//
// V2-specific receipt list schemas for the /api/v2/receipt/recent endpoint.
//
// NOTE: This schema uses V2 field naming conventions:
//   - `received` / `notreceived` arrays (V2 backward-compat names)
//   - V3 uses `revealed_receipts` / `pending_receipts` instead
//
// The V2 API maintains backward compatibility by preserving original field names.
// See shapes/v3/receipt.ts for the clean V3 schema with canonical naming.

import { receiptBaseSchema } from '@/schemas/shapes/v2';
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

// The details for each record in list view (V2 field names)
export const receiptRecordsDetailsSchema = z.object({
  type: z.string(), // literally the word "list"
  scope: z.string().nullish(), // 'org', 'domain', or null for default (customer)
  scope_label: z.string().nullish(), // Display name for the scope (org name or domain)
  since: z.number(),
  now: transforms.fromString.date,
  has_items: transforms.fromString.boolean,
  received: z.array(receiptRecordsSchema), // V2 name; V3 uses `revealed_receipts`
  notreceived: z.array(receiptRecordsSchema), // V2 name; V3 uses `pending_receipts`
});

export type ReceiptRecords = z.infer<typeof receiptRecordsSchema>;
export type ReceiptRecordsDetails = z.infer<typeof receiptRecordsDetailsSchema>;
