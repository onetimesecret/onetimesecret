// src/schemas/contracts/config/section/storage.ts

/**
 * Storage Configuration Schema
 *
 * Maps to the `redis:` section in config.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults and Redis database-number bounds live in
 * `shapes/config/section/storage.ts`.
 */

import { z } from 'zod';

/**
 * Redis database mapping
 * Maps database names to their Redis database numbers
 */
const redisDbsSchema = z.object({
  session: z.number().optional(),
  custom_domain: z.number().optional(),
  customer: z.number().optional(),
  metadata: z.number().optional(),
  secret: z.number().optional(),
  feedback: z.number().optional(),
});

/**
 * Redis/Valkey connection configuration
 */
const redisSchema = z.object({
  uri: z.string().optional(),
  dbs: redisDbsSchema.optional(),
});

/**
 * Storage schema (wraps redis for consistency with historical schema)
 */
const storageSchema = z.object({
  db: z
    .object({
      connection: z.object({
        url: z.string().optional(),
      }),
      database_mapping: z.record(z.string(), z.number().nullable()).optional(),
    })
    .optional(),
});

export { redisDbsSchema, redisSchema, storageSchema };
