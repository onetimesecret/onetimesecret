// src/schemas/api/account/responses/colonel-bannedips.ts
//
// Colonel (Admin) banned-IPs — NEW ban/unban ACK schemas (ticket #33).
//
// The banned-IPs LIST read side already has frozen schemas (`bannedIPSchema` /
// `bannedIPsDetailsSchema` in `./colonel` + `bannedIPsResponseSchema` in
// `../../internal/responses/colonel`); the BannedIPs screen REUSES those
// (CONTRACT 3 — reuse over duplication). This file adds ONLY the two shapes that
// had no frontend schema: the guarded ban + unban acks. Kept in a per-resource
// file so this screen never edits another screen's contract (CONTRACT 2 / the
// Zod tripwire — new schemas only).
//
// Shapes verified against the live logic classes
// (apps/api/colonel/logic/colonel/ban_ip.rb, unban_ip.rb): `banned_at` is a bare
// Unix-epoch number (mirroring the frozen `bannedIPSchema`, NOT transformed to
// Date), and the mutating endpoints echo a `record` + `details.message` envelope.

import { z } from 'zod';

// ============================================================================
// BanIP — guarded ban ack (POST /api/colonel/banned-ips)
// ============================================================================

/**
 * The created ban record (BanIP `record`). Mirrors {@link bannedIPSchema}, minus
 * transforms: `banned_at` stays a number (seconds). `banned_by` is whatever the
 * op stored (the acting colonel's objid from the UI path, or `cli` from the
 * shell) and is display-only.
 */
export const colonelBanIpRecordSchema = z.object({
  id: z.string(),
  ip_address: z.string(),
  reason: z.string().nullable(),
  banned_by: z.string().nullable(),
  banned_at: z.number(),
});

/** BanIP `details`: a human-readable ack message. */
export const colonelBanIpDetailsSchema = z.object({
  message: z.string(),
});

// ============================================================================
// UnbanIP — guarded unban ack (DELETE /api/colonel/banned-ips/:ip)
// ============================================================================

/** The unban confirmation (UnbanIP `record`). */
export const colonelUnbanIpRecordSchema = z.object({
  ip_address: z.string(),
  unbanned: z.boolean(),
});

/** UnbanIP `details`: a human-readable ack message. */
export const colonelUnbanIpDetailsSchema = z.object({
  message: z.string(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelBanIpRecord = z.infer<typeof colonelBanIpRecordSchema>;
export type ColonelBanIpDetails = z.infer<typeof colonelBanIpDetailsSchema>;
export type ColonelUnbanIpRecord = z.infer<typeof colonelUnbanIpRecordSchema>;
export type ColonelUnbanIpDetails = z.infer<typeof colonelUnbanIpDetailsSchema>;
