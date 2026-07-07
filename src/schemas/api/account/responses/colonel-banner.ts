// src/schemas/api/account/responses/colonel-banner.ts
//
// Colonel (Admin) broadcast banner — NEW get/set/clear schemas (ticket #41).
//
// The banner is a CLI-only power today (`bin/ots banner`); there was no colonel
// endpoint and therefore no existing frontend schema to reuse. These are all-new
// shapes (the Zod tripwire — new schemas only), kept in a per-resource file so
// this screen never edits another screen's contract (CONTRACT 2 / 3).
//
// Shapes verified against the live logic classes
// (apps/api/colonel/logic/colonel/{get,set,clear}_banner.rb):
//   - `content` is the raw HTML body (nullable when no banner is set).
//   - `ttl` is seconds-remaining, or null for a persistent / absent banner
//     (GetBanner collapses Redis's -1/-2 sentinels to null).
//   - `active` is the server's own is-set flag.

import { z } from 'zod';

// ============================================================================
// GetBanner — current banner (GET /api/colonel/banner)
// ============================================================================

/** The current banner record (GetBanner `record`), also echoed by SetBanner. */
export const colonelBannerRecordSchema = z.object({
  content: z.string().nullable(),
  ttl: z.number().nullable(),
  active: z.boolean(),
});

/** GetBanner `details`: the backing key + database (informational). */
export const colonelBannerDetailsSchema = z.object({
  key: z.string(),
  database: z.number(),
});

// ============================================================================
// SetBanner / ClearBanner — mutation acks
// ============================================================================

/** Shared mutation `details`: a human-readable ack message. */
export const colonelBannerMutationDetailsSchema = z.object({
  message: z.string(),
});

/** The clear confirmation (ClearBanner `record`). */
export const colonelBannerClearRecordSchema = z.object({
  cleared: z.boolean(),
  active: z.boolean(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelBannerRecord = z.infer<typeof colonelBannerRecordSchema>;
export type ColonelBannerDetails = z.infer<typeof colonelBannerDetailsSchema>;
export type ColonelBannerMutationDetails = z.infer<typeof colonelBannerMutationDetailsSchema>;
export type ColonelBannerClearRecord = z.infer<typeof colonelBannerClearRecordSchema>;
