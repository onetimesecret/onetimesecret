// src/schemas/api/internal/responses/colonel-banner.ts
//
// Wrapped response schemas for the colonel Broadcast Banner screen (ticket #41).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// All three envelopes are new (the banner had no colonel endpoint before this
// slice). The view imports these DIRECTLY (CONTRACT 3) so it typechecks
// independently of the registry; the Integrate step adds the registry keys from
// wiringInstructions.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  colonelBannerRecordSchema,
  colonelBannerDetailsSchema,
  colonelBannerMutationDetailsSchema,
  colonelBannerClearRecordSchema,
} from '@/schemas/api/account/responses/colonel-banner';
import { z } from 'zod';

// GET /api/colonel/banner → GetBanner
export const colonelBannerResponseSchema = createApiResponseSchema(
  colonelBannerRecordSchema,
  colonelBannerDetailsSchema
);

// POST /api/colonel/banner → SetBanner (echoes the new banner record)
export const colonelBannerSetResponseSchema = createApiResponseSchema(
  colonelBannerRecordSchema,
  colonelBannerMutationDetailsSchema
);

// DELETE /api/colonel/banner → ClearBanner
export const colonelBannerClearResponseSchema = createApiResponseSchema(
  colonelBannerClearRecordSchema,
  colonelBannerMutationDetailsSchema
);

export type ColonelBannerResponse = z.infer<typeof colonelBannerResponseSchema>;
export type ColonelBannerSetResponse = z.infer<typeof colonelBannerSetResponseSchema>;
export type ColonelBannerClearResponse = z.infer<typeof colonelBannerClearResponseSchema>;
