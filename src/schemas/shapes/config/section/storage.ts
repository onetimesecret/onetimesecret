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

import {
  redisDbsSchema,
  redisSchema,
  storageSchema,
} from '@/schemas/contracts/config/section/storage';
import { augment, type LeafTransform } from '@/schemas/utils/augment';

export { redisDbsSchema, redisSchema, storageSchema };

const dbNumber: LeafTransform = (n) => n.int().min(0).max(15).default(0);

const redisDbsShape = augment(redisDbsSchema, {
  session: dbNumber,
  custom_domain: dbNumber,
  customer: dbNumber,
  metadata: dbNumber,
  secret: dbNumber,
  feedback: dbNumber,
});

const redisShape = augment(redisSchema, {
  uri: (s) => s.default('redis://127.0.0.1:6379'),
  dbs: {
    session: dbNumber,
    custom_domain: dbNumber,
    customer: dbNumber,
    metadata: dbNumber,
    secret: dbNumber,
    feedback: dbNumber,
  },
});

const storageShape = augment(storageSchema, {
  db: {
    connection: { url: (s) => s.default('redis://localhost:6379') },
  },
});

export { redisDbsShape, redisShape, storageShape };
