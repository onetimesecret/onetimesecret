// src/schemas/api/internal/responses/colonel-elevation.ts
//
// The colonel step-up (sudo) window (#4327).
//
//   GET    /api/colonel/elevation → GetElevationStatus
//   POST   /api/colonel/elevation → ElevateSession
//   DELETE /api/colonel/elevation → DropElevation
//
// A dedicated contract rather than a field on GET /info: GetColonelInfo is
// pinned to the frozen `colonelInfo` shape in ./colonel.ts, which this epic
// deliberately does not disturb.
//
// Shapes verified against the logic classes in
// apps/api/colonel/logic/colonel/{get_elevation_status,elevate_session,drop_elevation}.rb.
// Epochs are bare Unix seconds; the console counts down CLIENT-SIDE from
// `expires_at` and never polls the endpoint (a poll would advance the session's
// last_activity_at on every tick and make #4331's idle timeout unreachable).

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

/**
 * The window itself. `expires_at` is null exactly when `elevated` is false —
 * which includes a window minted by a DIFFERENT identity in the same session,
 * since the server ignores those (a cookie can outlive an identity change).
 */
export const colonelElevationRecordSchema = z.object({
  elevated: z.boolean(),
  expires_at: z.number().nullable(),
  seconds_remaining: z.number(),
});

/**
 * Per-ACCOUNT capability, not global config. `factors` is what THIS operator
 * may use, so the console can render "your account has no password and no grace
 * is configured" instead of looping on an unsatisfiable prompt.
 *
 * `password_available` false + `factors` ['password'] is the SSO-only-no-grace
 * fork: nothing the operator can do from the browser, so the prompt shows the
 * remediation and no input.
 */
export const colonelElevationDetailsSchema = z.object({
  enabled: z.boolean(),
  window: z.number(),
  reauth_grace: z.number(),
  grace_available: z.boolean(),
  password_available: z.boolean(),
  factors: z.array(z.string()),
});

/**
 * POST's details name the factor the live window was minted with, so the banner
 * can label a `recent_auth` window distinctly while it is live — the weaker path
 * must be visible, not silent.
 */
export const colonelElevationGrantDetailsSchema = z.object({
  factor: z.string(),
  window: z.number(),
});

/** DELETE's details: a message plus whether anything was actually live. */
export const colonelElevationDropDetailsSchema = z.object({
  message: z.string(),
  was_elevated: z.boolean(),
});

export const colonelElevationStatusResponseSchema = createApiResponseSchema(
  colonelElevationRecordSchema,
  colonelElevationDetailsSchema
);

export const colonelElevationGrantResponseSchema = createApiResponseSchema(
  colonelElevationRecordSchema,
  colonelElevationGrantDetailsSchema
);

export const colonelElevationDropResponseSchema = createApiResponseSchema(
  colonelElevationRecordSchema,
  colonelElevationDropDetailsSchema
);

export type ColonelElevationRecord = z.infer<typeof colonelElevationRecordSchema>;
export type ColonelElevationDetails = z.infer<typeof colonelElevationDetailsSchema>;
export type ColonelElevationGrantDetails = z.infer<typeof colonelElevationGrantDetailsSchema>;
export type ColonelElevationStatusResponse = z.infer<typeof colonelElevationStatusResponseSchema>;
export type ColonelElevationGrantResponse = z.infer<typeof colonelElevationGrantResponseSchema>;
export type ColonelElevationDropResponse = z.infer<typeof colonelElevationDropResponseSchema>;
