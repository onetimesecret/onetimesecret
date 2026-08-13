// src/schemas/api/domains/responses/signin-config.ts
//
// Response schemas for domain signin configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/signin-config
// - PUT /api/domains/:domain_extid/signin-config
// - DELETE /api/domains/:domain_extid/signin-config

import { createApiResponseSchema } from '@/schemas/api/base';
import { authOverrideDetailsSchema } from '@/schemas/api/domains/responses/auth-override';
import {
  customDomainSigninConfigSchema,
  signinRestrictToSchema,
} from '@/schemas/shapes/domains/signin-config';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Response-specific details schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Server-resolved restriction for this domain (ADR-024 A2/A4).
 *
 * The wire form of `SigninConfig::RestrictToResolution`. The three states are
 * distinct on purpose and the client never collapses them:
 *
 * - `unrestricted` — every enabled method is offered (`restrict_to` is null)
 * - `restricted`   — only `restrict_to` is offered, from `source`
 * - `unavailable`  — a restriction stands but its method cannot run here, so
 *   sign-in offers nothing. `restrict_to` still names the method, so the UI
 *   can render "SSO required (not available on this domain)" rather than a
 *   blank state. This is the state the display field `features.restrict_to`
 *   (string-or-null) cannot express; nothing here may project it to null.
 *
 * `source` says which side the resolution came from: `global` (install),
 * `domain` (this domain's config), or `conflict` — global and domain each
 * name a DIFFERENT method, which has no intersection and fails closed
 * (ADR-024 A8). A conflict names the GLOBAL method, the one still in force.
 */
export const effectiveRestrictToSchema = z.object({
  state: z.enum(['unrestricted', 'restricted', 'unavailable']),
  /**
   * The method named by the restriction, null when unrestricted. Resilient
   * parse: an unrecognized method degrades to null while `state` keeps
   * carrying the truth (an invalid persisted value resolves `unavailable`).
   */
  restrict_to: signinRestrictToSchema.nullable().catch(null),
  source: z.enum(['domain', 'global', 'conflict']),
});

export type EffectiveRestrictTo = z.infer<typeof effectiveRestrictToSchema>;

/**
 * Tenant-SSO availability verdict (#4111): the runtime ladder's answer to
 * "why isn't SSO being offered on my sign-in page?", serialized once by the
 * server. `unavailable_reason` is the blocking rung
 * (`no_sso_config`, `sso_config_disabled`, `sso_not_permitted`,
 * `auth_disabled`, `unsupported_provider_type`), null when available.
 *
 * Left as a plain string: the rung list is a backend enumeration and a new
 * rung must not fail response parse. The UI maps known rungs to copy and
 * falls back to a generic line.
 */
export const tenantSsoVerdictSchema = z.object({
  available: z.boolean(),
  unavailable_reason: z.string().nullable().default(null),
});

export type TenantSsoVerdict = z.infer<typeof tenantSsoVerdictSchema>;

/**
 * Signin config response details schema (ADR-024).
 *
 * Shared auth-override resolution details plus the install-level method
 * restriction, the resolved effective restriction, and the tenant-SSO
 * verdict. The settings UI displays these; it never re-derives them.
 */
export const signinConfigDetailsSchema = authOverrideDetailsSchema.extend({
  /**
   * Install-level restrict_to — the INHERITED restriction, shown as such.
   * What actually resolves for this domain is `effective_restrict_to`.
   * Resilient parse: an unrecognized value degrades to null.
   */
  global_restrict_to: signinRestrictToSchema.nullable().catch(null).optional(),

  /**
   * Resolver output (ADR-024 A4). Required: the settings UI seeds an
   * unconfigured domain from it and every save materializes that seed, so a
   * response without it must fail parse rather than let the client guess.
   */
  effective_restrict_to: effectiveRestrictToSchema,

  /** Tenant-SSO availability verdict (#4111). */
  tenant_sso: tenantSsoVerdictSchema.optional(),
});

export type SigninConfigDetails = z.infer<typeof signinConfigDetailsSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Response schema for GET /api/domains/:domain_extid/signin-config
 *
 * `record` is null when the domain has no signin config — unconfigured is a
 * first-class state (200, not 404) so `details` can carry the inherited
 * global state (ADR-024).
 *
 * `details` is REQUIRED (overriding the envelope's optional default): the
 * settings UI seeds unconfigured domains from it and every save materializes
 * that seed as an explicit override, so a details-less response must fail
 * parse rather than let a guessed seed get persisted.
 */
export const getSigninConfigResponseSchema = createApiResponseSchema(
  customDomainSigninConfigSchema.nullable(),
  signinConfigDetailsSchema
).extend({
  details: signinConfigDetailsSchema,
});

export type GetSigninConfigResponse = z.infer<typeof getSigninConfigResponseSchema>;

/**
 * Response schema for PUT /api/domains/:domain_extid/signin-config
 *
 * `details` is REQUIRED — same contract as the GET schema.
 */
export const putSigninConfigResponseSchema = createApiResponseSchema(
  customDomainSigninConfigSchema,
  signinConfigDetailsSchema
).extend({
  details: signinConfigDetailsSchema,
});

export type PutSigninConfigResponse = z.infer<typeof putSigninConfigResponseSchema>;

/**
 * Response schema for DELETE /api/domains/:domain_extid/signin-config
 *
 * Carries post-delete resolution details (effective == global) so the
 * settings UI can re-render without a refetch.
 */
export const deleteSigninConfigResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
  details: signinConfigDetailsSchema.optional(),
});

export type DeleteSigninConfigResponse = z.infer<typeof deleteSigninConfigResponseSchema>;
