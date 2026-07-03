// src/schemas/contracts/custom-domain/homepage-config.ts
//
// Homepage configuration contract — per-domain homepage secrets settings.
// Gated by the homepage_secrets entitlement (available on free plan).
//
// Architecture: contract -> shape -> API

import { z } from 'zod';

import { disabledHomepageVariantSchema } from '@/schemas/contracts/disabled-homepage';

// ─────────────────────────────────────────────────────────────────────────────
// Homepage secrets mode
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Which interactive experience an enabled homepage presents to anonymous
 * visitors:
 * - 'create': the classic secret-creation form (historical behavior)
 * - 'incoming': the incoming-secrets form (send a secret TO the domain's
 *   configured recipients)
 *
 * Not to be confused with the site-level `homepage_mode`
 * (internal/external CIDR gating): that decides WHO sees the interactive
 * homepage; this decides WHAT the interactive homepage is.
 *
 * @category Contracts
 */
export const homepageSecretsModeSchema = z.enum(['create', 'incoming']);

/** TypeScript type for the homepage secrets mode. */
export type HomepageSecretsMode = z.infer<typeof homepageSecretsModeSchema>;

/** Default homepage secrets mode (the historical create-form behavior). */
export const DEFAULT_HOMEPAGE_SECRETS_MODE: HomepageSecretsMode = 'create';

// ─────────────────────────────────────────────────────────────────────────────
// Homepage config canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical homepage configuration contract.
 *
 * Controls whether anonymous users can create secrets on the domain's
 * public homepage. Managed via the /homepage-config endpoint, gated
 * by the homepage_secrets entitlement.
 *
 * @category Contracts
 */
export const homepageConfigCanonical = z.object({
  /** Domain ID (references CustomDomain.identifier). */
  domain_id: z.string(),

  /** Whether homepage secrets is enabled for this domain. */
  enabled: z.boolean().default(false),

  /**
   * Which interactive experience the enabled homepage presents
   * ('create' | 'incoming').
   *
   * `.catch('create')` over `.default('create')`: a future backend may emit
   * a mode this frontend version doesn't recognise; degrading to the
   * historical create behavior (whose API gate independently rejects
   * anonymous creation on incoming-mode domains) is preferable to crashing
   * the whole bootstrap payload parse. Also covers payloads from older
   * backends that omit the field entirely.
   */
  secrets_mode: homepageSecretsModeSchema.catch(DEFAULT_HOMEPAGE_SECRETS_MODE),

  /**
   * Whether the Sign Up link renders on this domain's homepage.
   * Defaults to false (link hidden) — operators opt in per-domain via
   * PUT /homepage-config. The site-level authentication.signup flag
   * remains the master switch — the frontend ANDs both layers.
   */
  signup_enabled: z.boolean().default(false),

  /**
   * Whether the Sign In link renders on this domain's homepage.
   * Defaults to false (link hidden) — operators opt in per-domain via
   * PUT /homepage-config. The site-level authentication.signin flag
   * remains the master switch — the frontend ANDs both layers.
   */
  signin_enabled: z.boolean().default(false),

  /**
   * Which disabled-homepage variant this domain renders when the homepage
   * secret form is gated by auth. Null means "use the frontend default"
   * (DEFAULT_DISABLED_HOMEPAGE_VARIANT) — operators only set this when
   * they want to deviate from the deployment-wide default.
   *
   * `.catch(null)` over `.default(null)`: a future backend may emit a
   * variant id this frontend version doesn't recognise; degrading to
   * null (and thus to the frontend default) is preferable to crashing
   * the whole bootstrap payload parse.
   *
   * The ?variant URL override still wins for dogfood/preview.
   */
  disabled_homepage_variant: disabledHomepageVariantSchema.nullable().catch(null),

  /** Configuration creation timestamp (Unix epoch seconds). Null if unconfigured. */
  created_at: z.number().nullable(),

  /** Last update timestamp (Unix epoch seconds). Null if unconfigured. */
  updated_at: z.number().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for homepage configuration. */
export type HomepageConfigCanonical = z.infer<typeof homepageConfigCanonical>;
