// src/schemas/api/internal/responses/colonel-emailtools.ts
//
// Wrapped response schemas for the colonel Email + Rate-limit Tools screen
// (ticket #44). Internal-only; consumed by the Vue admin console, never exposed
// publicly.
//
// All six envelopes are new (these capabilities had no colonel endpoint before
// this slice). The view imports these DIRECTLY (CONTRACT 3) so it typechecks
// independently of the registry; the Integrate step adds the registry keys from
// wiringInstructions.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  colonelEmailTemplatesRecordSchema,
  colonelEmailTemplatesDetailsSchema,
  colonelEmailPreviewRecordSchema,
  colonelEmailPreviewDetailsSchema,
  colonelEmailTestRecordSchema,
  colonelEmailTestDetailsSchema,
  colonelRateLimitersRecordSchema,
  colonelRateLimitersDetailsSchema,
  colonelRateLimitInspectRecordSchema,
  colonelRateLimitInspectDetailsSchema,
  colonelRateLimitResetRecordSchema,
  colonelRateLimitResetDetailsSchema,
} from '@/schemas/api/account/responses/colonel-emailtools';
import { z } from 'zod';

// GET /api/colonel/email/templates → ListEmailTemplates
export const colonelEmailTemplatesResponseSchema = createApiResponseSchema(
  colonelEmailTemplatesRecordSchema,
  colonelEmailTemplatesDetailsSchema
);

// GET /api/colonel/email/templates/:template/preview → PreviewEmailTemplate
export const colonelEmailPreviewResponseSchema = createApiResponseSchema(
  colonelEmailPreviewRecordSchema,
  colonelEmailPreviewDetailsSchema
);

// POST /api/colonel/email/test → SendTestEmail
export const colonelEmailTestResponseSchema = createApiResponseSchema(
  colonelEmailTestRecordSchema,
  colonelEmailTestDetailsSchema
);

// GET /api/colonel/ratelimit/limiters → ListRateLimiters
export const colonelRateLimitersResponseSchema = createApiResponseSchema(
  colonelRateLimitersRecordSchema,
  colonelRateLimitersDetailsSchema
);

// GET /api/colonel/ratelimit/inspect → InspectRateLimit
export const colonelRateLimitInspectResponseSchema = createApiResponseSchema(
  colonelRateLimitInspectRecordSchema,
  colonelRateLimitInspectDetailsSchema
);

// POST /api/colonel/ratelimit/reset → ResetRateLimit
export const colonelRateLimitResetResponseSchema = createApiResponseSchema(
  colonelRateLimitResetRecordSchema,
  colonelRateLimitResetDetailsSchema
);

export type ColonelEmailTemplatesResponse = z.infer<typeof colonelEmailTemplatesResponseSchema>;
export type ColonelEmailPreviewResponse = z.infer<typeof colonelEmailPreviewResponseSchema>;
export type ColonelEmailTestResponse = z.infer<typeof colonelEmailTestResponseSchema>;
export type ColonelRateLimitersResponse = z.infer<typeof colonelRateLimitersResponseSchema>;
export type ColonelRateLimitInspectResponse = z.infer<typeof colonelRateLimitInspectResponseSchema>;
export type ColonelRateLimitResetResponse = z.infer<typeof colonelRateLimitResetResponseSchema>;
