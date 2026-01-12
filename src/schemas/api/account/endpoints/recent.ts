// src/schemas/api/account/endpoints/recent.ts

import { receiptBaseSchema } from '@/schemas/models';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Receipt shape in list view
export const receiptRecordsSchema = receiptBaseSchema.merge(
  z.object({
    custid: z.string().nullish(),
    owner_id: z.string().nullish(),
    secret_ttl: z.union([z.string(), z.number()]).transform(Number),
    show_recipients: transforms.fromString.boolean,
    is_received: transforms.fromString.boolean,
    is_burned: transforms.fromString.boolean,
    is_orphaned: transforms.fromString.boolean,
    is_destroyed: transforms.fromString.boolean,
    identifier: z.string().nullish(),
    secret_shortid: z.string().nullish(),
    key: z.string().nullish(),
  })
);

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
