// src/schemas/api/v1/responses/registry.ts
//
// V1 response schema registry. Assembles V1-specific response schemas
// into the responseSchemas lookup object for the OpenAPI generator.
//
// V1 uses prefixed keys (v1Receipt, v1Status, etc.) to avoid collision
// with V2/V3 keys when all registries are merged for validation.

import { z } from 'zod';

import {
  v1ReceiptResponseSchema,
  v1ReceiptListResponseSchema,
  v1SecretRevealResponseSchema,
  v1BurnSecretResponseSchema,
} from './secrets';

// V1 status returns {status, locale} without a `success` field.
export const v1StatusResponseSchema = z.object({
  status: z.string(),
  locale: z.string(),
});

export type V1StatusResponse = z.infer<typeof v1StatusResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Response schema registry
// ─────────────────────────────────────────────────────────────────────────────

/** Keyed lookup of all V1 response schemas. */
export const responseSchemas = {
  v1Status: v1StatusResponseSchema,
  v1Receipt: v1ReceiptResponseSchema,
  v1ReceiptList: v1ReceiptListResponseSchema,
  v1SecretReveal: v1SecretRevealResponseSchema,
  v1BurnSecret: v1BurnSecretResponseSchema,
} as const;

// Legacy export name for backward compatibility with V3's spread import
export const v1ResponseSchemas = responseSchemas;

// ─────────────────────────────────────────────────────────────────────────────
// Mapped types
// ─────────────────────────────────────────────────────────────────────────────

export type ResponseTypes = {
  [K in keyof typeof responseSchemas]: z.infer<(typeof responseSchemas)[K]>;
};
