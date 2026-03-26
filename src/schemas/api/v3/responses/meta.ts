// src/schemas/api/v3/responses/meta.ts
//
// V3 JSON wire-format schemas for meta endpoints (status, version, locales).
// V3 omits the `success` field — HTTP status codes indicate success/error.
// V2 includes `success: boolean` in responses; see v2/responses/meta.ts.

import { z } from 'zod';

export const systemStatusResponseSchema = z.object({
  status: z.string(),
  locale: z.string(),
});

export const systemVersionResponseSchema = z.object({
  version: z.array(z.union([z.string(), z.number()])),
  locale: z.string(),
});

export const supportedLocalesResponseSchema = z.object({
  locales: z.array(z.string()),
  default_locale: z.string(),
  locale: z.string(),
});

export type SystemStatusResponse = z.infer<typeof systemStatusResponseSchema>;
export type SystemVersionResponse = z.infer<typeof systemVersionResponseSchema>;
export type SupportedLocalesResponse = z.infer<typeof supportedLocalesResponseSchema>;
