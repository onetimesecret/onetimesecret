// src/schemas/contracts/config/section/storage.ts

/**
 * Storage Configuration Schema
 *
 * Maps to the `redis:` section in config.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults and value constraints (e.g. Redis db number range 0-15) belong in
 * shapes — not here.
 */

import { z } from 'zod';

/**
 * Redis database mapping
 * Maps database names to their Redis database numbers.
 */
const redisDbsSchema = z.object({
  session: z.number(),
  custom_domain: z.number(),
  customer: z.number(),
  metadata: z.number(),
  secret: z.number(),
  feedback: z.number(),
});

/**
 * Redis/Valkey connection configuration
 */
const redisSchema = z.object({
  uri: z.string(),
  dbs: redisDbsSchema.optional(),
});

/**
 * Storage schema (wraps redis for consistency with historical schema)
 */
const storageSchema = z.object({
  db: z
    .object({
      connection: z.object({
        url: z.string(),
      }),
      database_mapping: z.record(z.string(), z.number().nullable()).optional(),
    })
    .optional(),
});

export { redisDbsSchema, redisSchema, storageSchema };
