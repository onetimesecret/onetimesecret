import { metadataBaseSchema } from '@/schemas/models';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod/v4';

// Metadata shape in list view
export const metadataRecordsSchema = metadataBaseSchema.merge(
  z.object({
    custid: z.string(),
    secret_ttl: z.union([z.string(), z.number()]).transform(Number),
    show_recipients: transforms.fromString.boolean,
    is_received: transforms.fromString.boolean,
    is_burned: transforms.fromString.boolean,
    is_orphaned: transforms.fromString.boolean,
    is_destroyed: transforms.fromString.boolean,
    is_truncated: transforms.fromString.boolean,
    identifier: z.string(),
  })
);

// The details for each record in list view
export const metadataRecordsDetailsSchema = z.object({
  type: z.string(), // literally the word "list"
  since: z.number(),
  now: transforms.fromString.date,
  has_items: transforms.fromString.boolean,
  received: z.array(metadataRecordsSchema),
  notreceived: z.array(metadataRecordsSchema),
});

export type MetadataRecords = z.infer<typeof metadataRecordsSchema>;
export type MetadataRecordsDetails = z.infer<typeof metadataRecordsDetailsSchema>;
