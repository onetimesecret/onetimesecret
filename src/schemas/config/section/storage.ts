// src/schemas/config/section/storage.ts

/**
 * Storage Configuration Schema
 *
 * Maps to the `redis:` section in config.defaults.yaml
 */

import { z } from 'zod/v4';

/**
 * Redis database mapping
 * Maps database names to their Redis database numbers (0-15)
 */
const redisDbsSchema = z.object({
  session: z.number().int().min(0).max(15).default(0),
  custom_domain: z.number().int().min(0).max(15).default(0),
  customdomain: z.number().int().min(0).max(15).default(0), // Alias
  customer: z.number().int().min(0).max(15).default(0),
  metadata: z.number().int().min(0).max(15).default(0),
  secret: z.number().int().min(0).max(15).default(0),
  feedback: z.number().int().min(0).max(15).default(0),
});

/**
 * Redis/Valkey connection configuration
 */
const redisSchema = z.object({
  uri: z.string().default('redis://127.0.0.1:6379'),
  dbs: redisDbsSchema.optional(),
});

/**
 * Storage schema (wraps redis for consistency with historical schema)
 */
const storageSchema = z.object({
  db: z.object({
    connection: z.object({
      url: z.string().default('redis://localhost:6379'),
    }),
    database_mapping: z.record(z.string(), z.number().nullable()).optional(),
  }).optional(),
});

export { redisSchema, redisDbsSchema, storageSchema };
