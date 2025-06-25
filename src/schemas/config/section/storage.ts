// src/schemas/config/storage.ts

import { z } from 'zod/v4';

const storageDbConnectionSchema = z.object({
  url: z.string().default('redis://localhost:6379'),
});

// 'connection' is required for 'db' (if 'db' exists and is not optional
// itself)
const storageDbSchema = z.object({
  // Ensure connection object is created by default
  connection: storageDbConnectionSchema,
  // Allow null for database_mapping values
  database_mapping: z.record(z.string(), z.number().nullable()).optional(),
});

/**
 * Storage Database Schema Configuration
 *
 * The 'db' property within 'storage' is configured as optional based on the current
 * JSON schema specification. This design decision reflects the following considerations:
 *
 * Schema Requirements Analysis:
 * - The JSON schema does not include 'db' in storage.required array
 * - Therefore 'db' remains optional at the storage level
 *
 * Default Value Behavior:
 * - If 'db' is present: Internal .default({}) for 'connection' applies automatically
 * - If 'db' is absent: No database configuration is generated
 *
 * Alternative Implementation:
 * If the schema required 'db' to always exist when 'storage' is present:
 * ```
 * db: storageDbSchema.default({})
 * ```
 *
 * Current Implementation Rationale:
 * Maintains schema compliance while allowing flexible storage configurations.
 * The Ruby default generator will only create database configuration when
 * explicitly specified, preventing unnecessary Redis connection attempts.
 */
const storageSchema = z.object({
  // Kept optional per existing JSON schema. If db were required for storage,
  // it would need .default({})
  db: storageDbSchema.optional(),
});

export { storageSchema };
