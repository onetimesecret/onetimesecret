// src/schemas/api/v2/responses/meta.ts
//
// V2 JSON wire-format schemas for meta endpoints (status, version, locales).
// These return simple flat objects — no record/details envelope.
//
// V2 includes `success: true` in responses. V3 omits success (uses HTTP status codes).

import { z } from 'zod';

export const systemStatusResponseSchema = z.object({
  success: z.boolean(),
  status: z.string(),
  locale: z.string(),
});

export const systemVersionResponseSchema = z.object({
  success: z.boolean(),
  version: z.array(z.union([z.string(), z.number()])),
  locale: z.string(),
});

export const supportedLocalesResponseSchema = z.object({
  success: z.boolean(),
  locales: z.array(z.string()),
  default_locale: z.string(),
  locale: z.string(),
});

export type SystemStatusResponse = z.infer<typeof systemStatusResponseSchema>;
export type SystemVersionResponse = z.infer<typeof systemVersionResponseSchema>;
export type SupportedLocalesResponse = z.infer<typeof supportedLocalesResponseSchema>;
