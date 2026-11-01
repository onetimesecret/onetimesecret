// src/schemas/api/internal/responses/colonel-reauthenticate.ts
//
// Re-authenticating an expired admin session by password (#4331 recovery).
//
//   POST /api/colonel/reauthenticate   body { password }
//
// The one /api/colonel route exempt from the admin session's idle/absolute
// bound, so it answers while every other console call 401s with
// `admin_session_expired`. On success the server has moved the session to a
// new id and re-stamped `authenticated_at`; it does NOT grant a step-up window
// (that stays a separate, explicit gesture — see ./colonel-elevation.ts).
//
// A refused password is a 403 `{ error, error_code: 'reauthentication_failed' }`
// and never reaches this schema: the console renders the `error` string.

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

/** `authenticated_at` is bare Unix seconds, the new start of the admin bound. */
export const colonelReauthenticateRecordSchema = z.object({
  reauthenticated: z.boolean(),
  authenticated_at: z.number(),
});

/**
 * Whether the session moved to a new id. The console adopts the new snapshot
 * epoch either way (one auth-mutation refresh), then reloads the page.
 */
export const colonelReauthenticateDetailsSchema = z.object({
  session_rotated: z.boolean(),
});

export const colonelReauthenticateResponseSchema = createApiResponseSchema(
  colonelReauthenticateRecordSchema,
  colonelReauthenticateDetailsSchema
);

export type ColonelReauthenticateRecord = z.infer<typeof colonelReauthenticateRecordSchema>;
export type ColonelReauthenticateResponse = z.infer<typeof colonelReauthenticateResponseSchema>;
