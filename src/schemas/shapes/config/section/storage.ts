// src/schemas/shapes/config/section/storage.ts

/**
 * Storage Configuration Shape
 *
 * Adds runtime defaults and Redis database-number bounds (0–15) on top of
 * the type-only storage contract. The bounds are an early-warning gate;
 * Redis rejects invalid database numbers at connection time, but the CLI
 * catches them first with a clearer error.
 *
 * @see src/schemas/contracts/config/section/storage.ts
 */

import { z } from 'zod';

export {
  redisDbsSchema,
  redisSchema,
  storageSchema,
} from '@/schemas/contracts/config/section/storage';

const redisDbsShape = z.object({
  session: z.number().int().min(0).max(15).default(0),
  custom_domain: z.number().int().min(0).max(15).default(0),
  customer: z.number().int().min(0).max(15).default(0),
  metadata: z.number().int().min(0).max(15).default(0),
  secret: z.number().int().min(0).max(15).default(0),
  feedback: z.number().int().min(0).max(15).default(0),
});

const redisShape = z.object({
  uri: z.string().default('redis://127.0.0.1:6379'),
  dbs: redisDbsShape.optional(),
});

const storageShape = z.object({
  db: z
    .object({
      connection: z.object({
        url: z.string().default('redis://localhost:6379'),
      }),
      database_mapping: z.record(z.string(), z.number().nullable()).optional(),
    })
    .optional(),
});

export { redisDbsShape, redisShape, storageShape };
