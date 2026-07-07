// src/schemas/api/internal/responses/colonel-bannedips.ts
//
// Wrapped response schemas for the colonel BannedIPs screen (ticket #33).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The banned-IPs LIST reuses the existing `bannedIPsResponseSchema` from
// ./colonel (re-exported here so the view has a single per-resource import
// surface — CONTRACT 3, reuse not duplicate). This file WRAPS only the two new
// single-record envelopes: the guarded ban + unban acks.
//
// The view imports these DIRECTLY (CONTRACT 3) so it typechecks independently of
// the registry; the Integrate step adds the registry keys from wiringInstructions.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  colonelBanIpRecordSchema,
  colonelBanIpDetailsSchema,
  colonelUnbanIpRecordSchema,
  colonelUnbanIpDetailsSchema,
} from '@/schemas/api/account/responses/colonel-bannedips';
import { z } from 'zod';

// Re-export the REUSED list schema so the BannedIPs view imports every banned-IP
// contract from this one per-resource file (the schema itself lives in ./colonel
// and is untouched — the Zod tripwire).
export { bannedIPsResponseSchema } from './colonel';
export type { BannedIPsResponse } from './colonel';

// POST /api/colonel/banned-ips → BanIP
export const colonelBanIpResponseSchema = createApiResponseSchema(
  colonelBanIpRecordSchema,
  colonelBanIpDetailsSchema
);

// DELETE /api/colonel/banned-ips/:ip → UnbanIP
export const colonelUnbanIpResponseSchema = createApiResponseSchema(
  colonelUnbanIpRecordSchema,
  colonelUnbanIpDetailsSchema
);

export type ColonelBanIpResponse = z.infer<typeof colonelBanIpResponseSchema>;
export type ColonelUnbanIpResponse = z.infer<typeof colonelUnbanIpResponseSchema>;
