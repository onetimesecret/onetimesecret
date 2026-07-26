// src/schemas/api/domains/responses/auth-override.ts
//
// Shared `details` contract for the per-domain auth override endpoints
// (signin-config, signup-config). Defined once so both features consume the
// backend resolver's output through the same shape (ADR-024).
//
// The backend serializes these alongside `record` on GET/PUT/DELETE:
// - global_enabled: install-level capability (the kill-switch input)
// - effective_enabled: the resolver's output for this domain — what actually
//   runs. The settings UI displays this value; it never re-derives
//   availability from the raw flag pair (that drift is what ADR-024 kills).

import { z } from 'zod';

/**
 * Resolution details common to signin-config and signup-config responses.
 *
 * REQUIRED on GET/PUT responses (PR #3817): the settings UI seeds
 * unconfigured domains from these fields, so a details-less payload fails
 * parse instead of seeding a guess. Older backends that omit `details`
 * (or 404) surface as a failed load. DELETE responses still mark it
 * optional — they only refresh already-held details.
 */
export const authOverrideDetailsSchema = z.object({
  /** Whether the current user can manage this config. */
  can_manage: z.boolean().optional(),

  /** Install-level capability (site.authentication enabled && signin/signup). */
  global_enabled: z.boolean(),

  /**
   * Resolver output for this domain: global for unconfigured domains,
   * `global && {feature}_enabled` for explicitly configured ones.
   */
  effective_enabled: z.boolean(),
});

export type AuthOverrideDetails = z.infer<typeof authOverrideDetailsSchema>;
