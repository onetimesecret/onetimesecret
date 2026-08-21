// src/schemas/contracts/bootstrap.ts
// @see src/tests/stores/bootstrapStore.spec.ts - Test fixtures for this schema
//
// Single source of truth for bootstrap payload schema.
//
// This schema defines the contract for window.__BOOTSTRAP_ME__ data
// injected by the Ruby backend. It is used by:
// - Rhales for server-side validation (via <schema src="..."> in index.rue)
// - TypeScript for client-side type inference
// - Contract tests to ensure Ruby serializers match this schema
//
// After modifying this schema, run: `pnpm run build:schemas` to regenerate
// the JSON schemas used by Rhales middleware.
//
// Architecture: This contract defines canonical types (no transforms).
// Ruby serializers send already-typed data, so no wire-format coercion needed.

import type { Stripe } from 'stripe';
import { z } from 'zod';

// Import canonical schemas from contracts (NOT shapes, which have transforms)
import { CanonicalPlanIdSchema } from '@/schemas/contracts/config/billing';
import { featuresDomainsSchema } from '@/schemas/contracts/config/section/features';
import { regionsConfigSchema } from '@/schemas/contracts/config/section/jurisdiction';
import {
  brandSettingsCanonical,
  cornerStyleValues,
  fontFamilyValues,
  homepageConfigCanonical,
} from '@/schemas/contracts/custom-domain';
import { customerCanonical } from '@/schemas/contracts/customer';
import {
  disabledHomepageConfigSchema,
  disabledHomepageVariantSchema,
} from '@/schemas/contracts/disabled-homepage';

// ═══════════════════════════════════════════════════════════════════════════════
// LOCALE SCHEMAS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Locale info object with code, name, and enabled flag.
 */
export const localeInfoSchema = z.object({
  code: z.string(),
  name: z.string(),
  enabled: z.boolean().default(true),
});

// ═══════════════════════════════════════════════════════════════════════════════
// MESSAGE SCHEMAS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Flash message displayed to the user.
 */
export const messageSchema = z.object({
  type: z.enum(['success', 'error', 'info']),
  content: z.string(),
});

// ═══════════════════════════════════════════════════════════════════════════════
// UI CONFIGURATION SCHEMAS
// ═══════════════════════════════════════════════════════════════════════════════

export const footerLinkSchema = z.object({
  text: z.string().optional(),
  i18n_key: z.string().optional(),
  url: z.string(),
});

export const footerGroupSchema = z.object({
  name: z.string().optional(),
  i18n_key: z.string().optional(),
  links: z.array(footerLinkSchema).default([]),
});

export const footerLinksConfigSchema = z.object({
  enabled: z.boolean().default(false),
  groups: z.array(footerGroupSchema).default([]),
});

/**
 * Masthead layout knobs (presentation only). Brand identity — the logo
 * asset, its alt text, and the product name — comes from the flat
 * `brand_*` bootstrap fields (the `brand:` config block), not the header
 * (#3612). All knobs are nullable: unset means "use the surface default"
 * ('/' for href; show_name falls to the custom-logo heuristic).
 */
export const headerLogoSchema = z.object({
  href: z.string().nullish(),
  show_name: z.boolean().nullish(),
  /**
   * When true, render the logo at a larger size in the authenticated header.
   * Useful for rasterized brand assets that need visual presence alongside
   * the org/domain switchers. Defaults to false (compact 40px logo).
   */
  prominent: z.boolean().nullish(),
});

export const headerNavigationSchema = z.object({
  enabled: z.boolean().default(true),
});

export const headerConfigSchema = z.object({
  enabled: z.boolean().default(true),
  logo: headerLogoSchema.optional(),
  navigation: headerNavigationSchema.optional(),
});

/**
 * UI interface configuration schema controlling header and footer display.
 *
 * @example
 * // Minimal configuration (uses defaults)
 * const ui = { enabled: true };
 *
 * @example
 * // Full configuration with masthead layout knobs and footer links
 * // (brand identity — logo asset, product name — lives in the flat
 * // brand_* bootstrap fields, not here)
 * const ui = {
 *   enabled: true,
 *   header: {
 *     enabled: true,
 *     logo: { href: '/', show_name: true, prominent: false },
 *     navigation: { enabled: true },
 *   },
 *   footer_links: {
 *     enabled: true,
 *     groups: [
 *       {
 *         name: 'legal',
 *         links: [
 *           { i18n_key: 'web.footer.privacy', url: '/privacy' },
 *         ],
 *       },
 *     ],
 *   },
 *   workspace_links: {
 *     enabled: true,
 *     links: [
 *       { text: 'API Docs', url: 'https://docs.example.com/api' },
 *     ],
 *   },
 * };
 */
export const workspaceLinksConfigSchema = z.object({
  enabled: z.boolean().default(false),
  links: z.array(footerLinkSchema).default([]),
});

export const uiCapabilitiesSchema = z.object({
  burn: z.boolean().optional(),
  show: z.boolean().optional(),
  receipt: z.boolean().optional(),
  recipient: z.boolean().optional(),
});

export const uiHelpSchema = z.object({
  enabled: z.boolean().default(true),
});

/**
 * Public-facing links surfaced when the homepage secret form is gated by
 * auth. Recipients arriving via a shared link use these to learn about
 * the service. Each field is nullable; when null/empty the corresponding
 * affordance is hidden rather than rendered with a broken target.
 */
export const homepagePublicLinksSchema = z.object({
  recipient_intro: z.string().nullable().optional(),
});

/**
 * Homepage UI configuration: mode (CIDR/header gating) plus public-facing
 * links surfaced on the disabled-homepage view.
 */
export const homepageUiConfigSchema = z.object({
  public_links: homepagePublicLinksSchema.optional(),
  /**
   * Deployment-wide default disabled-homepage variant for the CANONICAL site,
   * from the `DEFAULT_DISABLED_HOMEPAGE_VARIANT` env var
   * (`site.interface.ui.homepage.disabled_variant`). Sits between the
   * per-domain `homepage_config.disabled_homepage_variant` and the frontend
   * `DEFAULT_DISABLED_HOMEPAGE_VARIANT` constant in the resolution chain.
   *
   * `.catch(null)` so an unrecognised value degrades to the frontend default
   * rather than failing the whole bootstrap parse.
   */
  disabled_variant: disabledHomepageVariantSchema.nullable().catch(null).optional(),
  /**
   * Deployment-wide default disabled-homepage variant for CUSTOM DOMAINS, from
   * the `DEFAULT_CUSTOM_DOMAIN_DISABLED_HOMEPAGE_VARIANT` env var
   * (`site.interface.ui.homepage.custom_disabled_variant`). Kept separate from
   * `disabled_variant` so the canonical default and the custom-domain default
   * stay decoupled (the canonical/custom split from `4effa3e3f5`). Sits between
   * the per-domain `homepage_config.disabled_homepage_variant` and the frontend
   * `DEFAULT_DISABLED_HOMEPAGE_VARIANT` constant — custom domains do NOT fall
   * back to the canonical `disabled_variant`.
   *
   * `.catch(null)` so an unrecognised value degrades to the frontend default
   * rather than failing the whole bootstrap parse.
   */
  custom_disabled_variant: disabledHomepageVariantSchema.nullable().catch(null).optional(),
});

export const uiInterfaceSchema = z.object({
  enabled: z.boolean().default(true),
  header: headerConfigSchema.optional(),
  footer_links: footerLinksConfigSchema.optional(),
  workspace_links: workspaceLinksConfigSchema.optional(),
  capabilities: uiCapabilitiesSchema.optional(),
  show_version: z.boolean().default(true),
  help: uiHelpSchema.optional(),
  homepage: homepageUiConfigSchema.optional(),
});

// ═══════════════════════════════════════════════════════════════════════════════
// API CONFIGURATION SCHEMAS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Guest route permissions for API access.
 */
export const apiGuestRoutesSchema = z.object({
  enabled: z.boolean().default(true),
  conceal: z.boolean().default(true),
  generate: z.boolean().default(true),
  reveal: z.boolean().default(true),
  burn: z.boolean().default(true),
  show: z.boolean().default(true),
  receipt: z.boolean().default(true),
});

/**
 * API interface configuration schema controlling API access and guest routes.
 */
export const apiInterfaceSchema = z.object({
  enabled: z.boolean().default(true),
  guest_routes: apiGuestRoutesSchema.default(apiGuestRoutesSchema.parse({})),
});

// ═══════════════════════════════════════════════════════════════════════════════
// AUTHENTICATION SCHEMAS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Inner authentication settings schema with defaults.
 * Separated from nullable wrapper to enable schema.parse({}) for defaults.
 */
const authenticationSettingsInner = z.object({
  enabled: z.boolean().default(true),
  signup: z.boolean().default(true),
  signin: z.boolean().default(true),
  autoverify: z.boolean().default(false),
  required: z.boolean().default(false),
  mode: z.enum(['simple', 'full']).optional(),
});

export const authenticationSettingsSchema = authenticationSettingsInner;

// ═══════════════════════════════════════════════════════════════════════════════
// SSO SCHEMAS
// ═══════════════════════════════════════════════════════════════════════════════

export const ssoProviderSchema = z.object({
  route_name: z.string(),
  display_name: z.string(),
});

export const ssoConfigSchema = z.object({
  enabled: z.boolean().default(false),
  providers: z.array(ssoProviderSchema).default([]),
  enforce_sso_only: z.boolean().default(false),
});

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURES SCHEMA
// ═══════════════════════════════════════════════════════════════════════════════

// Workaround: Zod's .default({}) doesn't cascade into inner field defaults which
// are needed for nested features objects. To ensure all nested defaults are
// applied, we extract the inner schema and use .default(inner.parse({})) to
// trigger default population at all levels. Extract inner schema and use
// .default(inner.parse({})) to trigger nested defaults.
//
// Check colinhacks/zod#5764 for decision on v4 native solution, and hopefully
// can simplify to something like: organizations: z.object({...}).default({}).
const organizationFeaturesInner = z.object({
  enabled: z.boolean().default(false),
  sso_enabled: z.boolean().default(false),
  custom_mail_enabled: z.boolean().default(false),
  incoming_secrets_enabled: z.boolean().default(false),
  // Default-ON (unlike siblings): only an explicit false — set via
  // ORGS_AUDIT_LOGS_ENABLED=false — hides the org Secret Activity tab.
  // Absent (older backends without the flag) keeps the feature enabled.
  audit_logs_enabled: z.boolean().default(true),
});

// Same cascade-default workaround as organizationFeaturesInner above.
const secretActivityFeaturesInner = z.object({
  // Default-ON: collection only stops on an explicit false — set via
  // SECRET_ACTIVITY_COLLECT=false (GDPR data minimization, #3990). Absent
  // (older backends without the flag) keeps events being recorded.
  collect_enabled: z.boolean().default(true),
  // Operator-configured retention cap (SECRET_ACTIVITY_MAX_EVENTS); the
  // backend clamps to a floor of 100 at read time, so a positive int is
  // the whole wire contract here.
  max_events: z.number().int().positive().default(10000),
  // Default-OFF (#3989): the country column is a legally-sensitive org-tier
  // geo feature pending counsel review, so it only appears on an explicit
  // true — set via SECRET_ACTIVITY_GEO_COUNTRY_ENABLED=true. Absent (the default,
  // and all older backends) keeps the column hidden. Inverse default of the
  // collect_enabled sibling above.
  geo_country_enabled: z.boolean().default(false),
});

const restrictToSchema = z.enum(['password', 'email_auth', 'webauthn', 'sso']);

/**
 * Domain-aware resolver output. Unlike the legacy scalar projection below,
 * this preserves an unavailable restriction so display code can fail closed.
 */
export const effectiveRestrictToSchema = z.object({
  state: z.enum(['unrestricted', 'restricted', 'unavailable']),
  restrict_to: restrictToSchema.nullable().catch(null),
  source: z.enum(['domain', 'global', 'conflict']),
});

export const featuresSchema = z.object({
  markdown: z.boolean().default(false),
  // Sign-in availability for the current domain context (AND of global
  // AUTH_SIGNIN and the domain SigninConfig). Only an explicit false
  // disables — it renders the public /signin page as a friendly "not
  // available" notice (#3415); true and undefined (older backends) both
  // keep the auth form.
  signin: z.boolean().optional(),
  mfa: z.boolean().optional(),
  lockout: z.boolean().optional(),
  password_requirements: z.boolean().optional(),
  email_auth: z.boolean().optional(),
  webauthn: z.boolean().optional(),
  sso: z.union([z.boolean(), ssoConfigSchema]).optional(),
  // Legacy scalar projection retained for existing consumers.
  restrict_to: restrictToSchema.nullable().optional(),
  // Explicit resolver state for display/runtime parity. Optional keeps
  // bootstraps from older backends valid; absence preserves prior behavior.
  effective_restrict_to: effectiveRestrictToSchema.optional(),
  magic_links: z.boolean().optional(),
  organizations: organizationFeaturesInner.default(organizationFeaturesInner.parse({})),
  secret_activity: secretActivityFeaturesInner.default(secretActivityFeaturesInner.parse({})),
});

// ═══════════════════════════════════════════════════════════════════════════════
// SECRET OPTIONS SCHEMA (canonical, no transforms)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Character set options for password generation.
 */
export const characterSetsSchema = z.object({
  uppercase: z.boolean().default(true),
  lowercase: z.boolean().default(true),
  numbers: z.boolean().default(true),
  symbols: z.boolean().default(false),
  exclude_ambiguous: z.boolean().default(true),
});

/**
 * Password generation settings.
 */
export const passwordGenerationSchema = z.object({
  default_length: z.number().int().min(4).max(128).default(12),
  length_options: z.array(z.number().int().min(4).max(128)).default([8, 12, 16, 20, 24, 32]),
  character_sets: characterSetsSchema.optional(),
});

/**
 * Passphrase settings.
 */
export const passphraseSchema = z.object({
  required: z.boolean().default(false),
  /**
   * Minimum length required for passphrases.
   * Default: 4. Set to 0 to disable enforcement.
   * @sync apps/api/v1/logic/secrets/base_secret_action.rb — passphrase validation
   */
  minimum_length: z.number().int().min(0).max(256).default(4),
  maximum_length: z.number().int().min(8).max(1024).default(128),
  enforce_complexity: z.boolean().default(false),
});

/**
 * Canonical secret options schema for bootstrap payload.
 * No transforms - Ruby serializers send already-typed data.
 */
export const secretOptionsSchema = z.object({
  default_ttl: z.number().int().positive().default(604800),
  // Max mirrors the server's absolute bound (WithEntitlements::MAX_TTL,
  // 365 days) so operator-configured options beyond 30 days survive
  // bootstrap validation (#4008). Per-caller ceilings apply at request time.
  ttl_options: z
    .array(z.number().int().positive().min(60).max(31536000))
    .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),
  /**
   * TTL ceiling the server silently applies to anonymous (guest) secrets, in
   * seconds. A hard product cap (7 days) that holds on every deployment,
   * billing enabled or not; TTL_MAX_ANONYMOUS can raise or lower it. Absent
   * only on a payload predating this field — treat that as "no ceiling".
   *
   * @sync apps/web/core/views/serializers/config_serializer.rb — anonymous_ttl_ceiling
   * @sync apps/api/v2/logic/secrets/base_secret_action.rb — anonymous_max_ttl
   * @sync lib/onetime/models/features/with_entitlements.rb — ANONYMOUS_MAX_TTL
   */
  ttl_max_anonymous: z.number().int().positive().nullish(),
  passphrase: passphraseSchema.optional(),
  password_generation: passwordGenerationSchema.optional(),
});

// ═══════════════════════════════════════════════════════════════════════════════
// DIAGNOSTICS SCHEMA (bootstrap-specific flat structure)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Sentry configuration for bootstrap payload.
 * Flat structure - differs from config YAML which has defaults/backend/frontend.
 */
export const sentryConfigSchema = z.object({
  dsn: z.string().default(''),
  enabled: z.boolean().default(false),
  debug: z.boolean().optional(),
  environment: z.string().optional(),
  release: z.string().optional(),
  sampleRate: z.number().min(0).max(1).optional(),
  tracesSampleRate: z.number().min(0).max(1).optional(),
  maxBreadcrumbs: z.number().optional(),
  logErrors: z.boolean().default(true),
  trackComponents: z.boolean().default(true),
});

/**
 * Inner diagnostics schema with defaults.
 */
const diagnosticsInner = z.object({
  sentry: sentryConfigSchema.default(sentryConfigSchema.parse({})),
});

/**
 * Diagnostics configuration for bootstrap payload.
 */
export const diagnosticsSchema = diagnosticsInner.nullable();

// ═══════════════════════════════════════════════════════════════════════════════
// DEVELOPMENT SCHEMA
// ═══════════════════════════════════════════════════════════════════════════════

export const developmentConfigSchema = z.object({
  enabled: z.boolean().default(false),
  domain_context_enabled: z.boolean().default(false),
});

// ═══════════════════════════════════════════════════════════════════════════════
// ORGANIZATION SCHEMA
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Organization schema - nullable since not all users have organizations.
 *
 * entitlements/limits are resolved server-side at the WithEntitlements
 * chokepoint (ADR-020), so they already reflect an active colonel preview.
 */
export const organizationSchema = z
  .object({
    objid: z.string(),
    extid: z.string(),
    display_name: z.string(),
    is_default: z.boolean(),
    planid: CanonicalPlanIdSchema.nullish(),
    current_user_role: z.enum(['owner', 'admin', 'member']).nullish(),
    entitlements: z.array(z.string()).nullish(),
    /** Plan limits per resource; -1 means unlimited. */
    limits: z
      .object({
        teams: z.number().optional(),
        total_members_per_org: z.number().optional(),
        custom_domains: z.number().optional(),
        /**
         * Max secret TTL in seconds for this org's plan; -1 = unlimited.
         * Same limit V2 enforces at secret creation.
         *
         * @sync apps/api/v2/logic/secrets/base_secret_action.rb — process_ttl
         */
        secret_lifetime: z.number().optional(),
      })
      .nullish(),
  })
  .nullable();

// ═══════════════════════════════════════════════════════════════════════════════
// DOMAIN STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

export const domainStrategySchema = z.enum(['canonical', 'subdomain', 'custom', 'invalid']);

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORTED TYPES (derived from sub-schemas defined in this file)
// ═══════════════════════════════════════════════════════════════════════════════

export type LocaleInfo = z.infer<typeof localeInfoSchema>;
export type Message = z.infer<typeof messageSchema>;
export type FooterLink = z.infer<typeof footerLinkSchema>;
export type FooterGroup = z.infer<typeof footerGroupSchema>;
export type FooterLinksConfig = z.infer<typeof footerLinksConfigSchema>;
export type WorkspaceLinksConfig = z.infer<typeof workspaceLinksConfigSchema>;
export type HeaderLogo = z.infer<typeof headerLogoSchema>;
export type HeaderNavigation = z.infer<typeof headerNavigationSchema>;
export type HeaderConfig = z.infer<typeof headerConfigSchema>;
export type UiCapabilities = z.infer<typeof uiCapabilitiesSchema>;
export type UiHelp = z.infer<typeof uiHelpSchema>;
export type UiInterface = z.infer<typeof uiInterfaceSchema>;
export type ApiGuestRoutes = z.infer<typeof apiGuestRoutesSchema>;
export type ApiInterface = z.infer<typeof apiInterfaceSchema>;
export type AuthenticationSettings = z.infer<typeof authenticationSettingsSchema>;
export type SSOProvider = z.infer<typeof ssoProviderSchema>;
export type SSOConfig = z.infer<typeof ssoConfigSchema>;
export type Features = z.infer<typeof featuresSchema>;
export type DevelopmentConfig = z.infer<typeof developmentConfigSchema>;
export type Organization = z.infer<typeof organizationSchema>;
export type DomainStrategy = z.infer<typeof domainStrategySchema>;

// Re-export types from contracts
export type { RegionsConfig } from '@/schemas/contracts/config/section/jurisdiction';
export type { BrandSettingsCanonical as BrandSettings } from '@/schemas/contracts/custom-domain';
export type { CustomerCanonical as Customer } from '@/schemas/contracts/customer';

// Types derived from local schemas
export type SecretOptions = z.infer<typeof secretOptionsSchema>;
export type SentryConfig = z.infer<typeof sentryConfigSchema>;
export type DiagnosticsConfig = z.infer<typeof diagnosticsSchema>;
export type CharacterSets = z.infer<typeof characterSetsSchema>;
export type PasswordGeneration = z.infer<typeof passwordGenerationSchema>;
export type Passphrase = z.infer<typeof passphraseSchema>;

// ═══════════════════════════════════════════════════════════════════════════════
// DIAGNOSTICS ACTOR (privacy-preserving actor identity for Sentry)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * The two — and only two — actor scopes the server is permitted to declare.
 *
 * THIS LABEL NAMES WHICH SECRET KEYED THE ACTOR REF. IT SAYS NOTHING ABOUT HOW
 * THE ACTOR AUTHENTICATED. The axis is correlation blast radius, not identity
 * provider — see `Onetime::Utils::DiagnosticsRef#keying`
 * (lib/onetime/utils/diagnostics_ref.rb):
 *
 * - `federated` — the ref was derived with `FEDERATION_SECRET`, which is shared
 *   across the regional instances of one federation. It is chosen ONLY when a
 *   residency scope also resolves (`DIAGNOSTICS_REF_REGION`, else the configured
 *   jurisdiction); with nothing declared the shared key is refused and the
 *   scope narrows to `deployment`.
 *
 *   THE CORRELATION RADIUS IS ONE JURISDICTION, NOT ONE FEDERATION. The
 *   residency scope is mixed into the pre-image unconditionally, so the same
 *   person yields DIFFERENT refs on the EU instance and the US instance of one
 *   federation — deliberately, because a region-independent ref would be a
 *   ready-made join key proving one data subject is present in both, which is
 *   the inference the residency architecture exists to prevent. What
 *   `federated` buys is correlation across installs that share the secret AND
 *   resolve to the SAME residency scope; that is still wider than one
 *   deployment, which is why the label is emitted at all.
 * - `deployment` — the ref was derived with this deployment's own
 *   `ACCOUNT_ID_SECRET`. The ref is meaningless anywhere else; correlation
 *   stops at this instance.
 *
 * NOT AN SSO SIGNAL — a real misreading worth naming, because the tag is
 * indexed and an operator WILL filter on it. A deployment that sets
 * `FEDERATION_SECRET` AND declares a residency (the precondition stated three
 * paragraphs up) emits `federated` for EVERY account it identifies, local
 * password accounts included; nothing about the label is conditioned on how
 * anyone signed in. Filtering `actor_scope:federated` in Sentry selects events
 * whose actor ref is federation-keyed, NOT events from SSO users. There is
 * deliberately no field in the diagnostics payload that reports how an actor
 * authenticated; that would be an authentication-posture disclosure with no
 * diagnostic use.
 *
 * (EXECUTED, so the example is not read as a shortcut past the precondition:
 * with `FEDERATION_SECRET` set and nothing else — no `DIAGNOSTICS_REF_REGION`, no
 * jurisdiction, no `ACCOUNT_ID_SECRET` — `DiagnosticsRef.keying` is nil, so no
 * diagnostics actor block is emitted at all and the question of a label does not
 * arise.
 * Add `ACCOUNT_ID_SECRET` and the label is `deployment`, not `federated`.)
 *
 * Modelled as a closed `z.enum` rather than `z.string()` on purpose: the value
 * becomes a Sentry TAG (`actor_scope`), tags are indexed and searchable, and an
 * unbounded string field on an indexed dimension is exactly how a free-text
 * identifier (an email, a plan name, an org slug) reaches Sentry one careless
 * server-side commit later. A new scope must be added HERE, in review, before it
 * can reach Sentry.
 */
export const ACTOR_SCOPES = ['federated', 'deployment'] as const;

/**
 * The EXACT permitted shape of `actor_ref`, and the single source of truth for
 * it on the TypeScript side.
 *
 * ## Why a content check and not just a type check
 *
 * `z.string().min(1)` validates the SHAPE of the block but says nothing about
 * what is inside the string. That gap is a laundering channel: a server bug, an
 * older build, or a compromised region node emitting
 * `{ actor_ref: "alice@example.com", actor_scope: "deployment" }` satisfies a
 * strictObject with two keys and a valid enum, and the value then flows through
 * `applyActorIdentity` into `user.id` — where the outbound sanitizer, which
 * strips `email`/`username`/`name`, keeps `id` verbatim on every error and
 * transaction. Validating the CONTENT closes it: an email cannot pass a
 * fixed-width hex test.
 *
 * ## The contract this mirrors
 *
 * Server side: `Onetime::Utils::DiagnosticsRef` (lib/onetime/utils/diagnostics_ref.rb)
 * emits `OpenSSL::HMAC.hexdigest('SHA256', …)[0, REF_LENGTH]` — LOWERCASE hex,
 * `REF_LENGTH = 16` chars (64 bits), deliberately half the width of a
 * federation email hash so the two are not confusable.
 *
 * These two constants are ONE contract in two languages. If `REF_LENGTH` or the
 * derivation changes (a widened digest, a jurisdiction prefix, a `v2` keying),
 * this pattern must change IN THE SAME COMMIT. It fails CLOSED, so a drifted
 * pattern does not leak — it silently drops actor correlation everywhere, which
 * is a real observability regression and the reason the coupling is called out
 * here rather than left to be discovered in Sentry.
 *
 * Anchored with `^`/`$` and non-global (no `g` flag): a `g`-flagged regex would
 * carry `lastIndex` between `.test()` calls and pass/fail alternately.
 */
export const ACTOR_REF_PATTERN = /^[0-9a-f]{16}$/;

/**
 * Content gate for a candidate actor reference.
 *
 * Exported so the outbound final gate (`sanitizeEventUser`) enforces the same
 * rule as the inbound parse without duplicating the literal. Non-strings and
 * anything that is not exactly `ACTOR_REF_PATTERN` are refused.
 *
 * @param value - Untrusted candidate, typically `event.user.id`.
 */
export function isActorRef(value: unknown): value is string {
  return typeof value === 'string' && ACTOR_REF_PATTERN.test(value);
}

/**
 * `diagnostics_actor` — the server-provided actor-identity block.
 *
 * ## Wire contract
 *
 * ```json
 * { "diagnostics_actor": { "actor_ref": "a1b2c3d4e5f60718",
 *                           "actor_scope": "federated" } }
 * ```
 *
 * The block is **ABSENT for anonymous sessions**. Absence is the signal — there
 * is no anonymous sentinel value, no empty string, no `null` actor. Hence
 * `.optional()` on the parent field rather than the `.default()` used by every
 * always-emitted serializer field elsewhere in this contract.
 *
 * ## Why `z.strictObject` and not `z.object`
 *
 * This is the one bootstrap sub-schema whose parsed output is handed to a
 * third-party processor (Sentry `scope.setUser`). Zod v4's plain `z.object`
 * STRIPS unknown keys silently; `z.strictObject` REJECTS the whole block. For
 * a privacy boundary, rejecting is the correct failure mode:
 *
 *   - Strip-on-unknown means a server that starts emitting
 *     `{ actor_ref, actor_scope, email }` produces a *valid* parse whose extra
 *     field merely happens not to be read today — one refactor away from being
 *     forwarded.
 *   - Reject-on-unknown means that same payload fails `safeParse`, the actor is
 *     never set, and the deployment runs unidentified. Losing actor correlation
 *     is recoverable; leaking an email to a third-party processor is not.
 *
 * See `src/plugins/core/diagnostics/actorIdentity.ts`, which is the only place
 * this schema is actually parsed against live data, for the enforcement.
 *
 * ## What this block must never carry
 *
 * `actor_ref` is an OPAQUE DETERMINISTIC REFERENCE. It is not an email, a
 * display name, a customer `objid`, a customer `extid`, an IP address, a
 * session id, or either of the two secret identifiers. The client cannot prove
 * that a value is a keyed digest, but it CAN require the exact shape one has —
 * 16 lowercase hex chars, `ACTOR_REF_PATTERN` — so no human-readable
 * identifier can occupy the field. That check is the difference between
 * refusing an unexpected KEY and refusing an unexpected VALUE; both are
 * required, because `user.id` is the one field the outbound sanitizer keeps.
 */
export const diagnosticsActorSchema = z.strictObject({
  /**
   * Opaque, deterministic, server-derived actor reference. Never PII.
   * Content-checked against ACTOR_REF_PATTERN, not merely non-empty.
   */
  actor_ref: z.string().regex(ACTOR_REF_PATTERN),
  /** Closed enum; becomes the indexed Sentry `actor_scope` tag. */
  actor_scope: z.enum(ACTOR_SCOPES),
});

/** Parsed shape of the `diagnostics_actor` bootstrap block. */
export type DiagnosticsActorBlock = z.infer<typeof diagnosticsActorSchema>;

/** One of the two permitted actor scopes. */
export type ActorScope = (typeof ACTOR_SCOPES)[number];

// ═══════════════════════════════════════════════════════════════════════════════
// BOOTSTRAP PAYLOAD SCHEMA (full payload for Rhales validation)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Bootstrap payload schema for window.__BOOTSTRAP_ME__.
 *
 * This schema validates the complete payload injected by Ruby serializers:
 * - ConfigSerializer fields
 * - AuthenticationSerializer fields
 * - DomainSerializer fields
 * - I18nSerializer fields
 * - MessagesSerializer fields
 * - SystemSerializer fields
 *
 * ## Schema contract pattern: `.default()` vs `.optional()`
 *
 * Use `.default(...)` for fields the Ruby serializer ALWAYS emits. This:
 * - Documents the actual contract (Ruby always sends it)
 * - Produces a non-optional TypeScript type (no unnecessary `?.` guards)
 * - Provides a fallback if parsing somehow receives `undefined`
 *
 * Use `.optional()` ONLY for fields Ruby conditionally emits (e.g., `regions`
 * is only sent when `regions_enabled` is true). The TypeScript type will
 * include `| undefined`, correctly reflecting the contract.
 *
 * When in doubt, check the Ruby serializer's `output_template` and the field
 * assignment logic to determine which pattern applies.
 */
export const bootstrapSchema = z.object({
  // ─────────────────────────────────────────────────────────────────────────────
  // ConfigSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  api: apiInterfaceSchema.default(apiInterfaceSchema.parse({})),
  authentication: authenticationSettingsSchema.default(authenticationSettingsInner.parse({})),
  d9s_enabled: z.boolean().default(false),
  diagnostics: diagnosticsSchema.default(diagnosticsInner.parse({})),
  docs_host: z.string().default(''),
  domains: featuresDomainsSchema.optional(),
  domains_enabled: z.boolean().default(false),
  features: featuresSchema.default(featuresSchema.parse({})),
  frontend_development: z.boolean().default(false),
  frontend_host: z.string().default(''),
  billing_enabled: z.boolean().default(false),
  regions: regionsConfigSchema.optional(),
  regions_enabled: z.boolean().default(false),
  secret_options: secretOptionsSchema.default(secretOptionsSchema.parse({})),
  site_host: z.string().default(''),
  support_email: z.string().default(''),
  support_host: z.string().default(''),
  checkout_host: z.string().default(''),
  ui: uiInterfaceSchema.default(uiInterfaceSchema.parse({})),
  available_jurisdictions: z.array(z.string()).default([]),

  // Frontend rendering config for the disabled-homepage view. All knobs
  // optional with auto-detection defaults; backend may omit entirely.
  disabled_homepage: disabledHomepageConfigSchema.default(disabledHomepageConfigSchema.parse({})),

  // ─────────────────────────────────────────────────────────────────────────────
  // Brand fields (per-installation defaults from OT.conf['brand'])
  //
  // Resolution order at the store layer:
  //   1. domain_branding.<field>           (per-domain, from Redis)
  //   2. bootstrapStore.brand_<field>      (per-installation, these fields)
  //   3. NEUTRAL_BRAND_DEFAULTS.<field>    (frontend neutral fallback)
  //
  // No `.default()` here by design — defaults flow through
  // NEUTRAL_BRAND_DEFAULTS at the store layer, not the schema. Eager
  // `.default()` would short-circuit the nullish-coalescing fallback chain.
  // ─────────────────────────────────────────────────────────────────────────────
  brand_primary_color: z.string().nullish(),
  brand_product_name: z.string().nullish(),
  brand_product_domain: z.string().nullish(),
  brand_support_email: z.string().nullish(),
  brand_corner_style: z.enum(cornerStyleValues).nullish(),
  brand_font_family: z.enum(fontFamilyValues).nullish(),
  brand_button_text_light: z.boolean().nullish(),
  brand_logo_url: z.string().nullish(),
  brand_logo_dark_url: z.string().nullish(),
  brand_logo_alt: z.string().nullish(),
  brand_favicon_url: z.string().nullish(),

  // ─────────────────────────────────────────────────────────────────────────────
  // AuthenticationSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  apitoken: z.string().optional(),
  authenticated: z.boolean().default(false),
  awaiting_mfa: z.boolean().optional().default(false),
  had_valid_session: z.boolean().default(false),
  // Tri-state: true/false are definitive; null means the server could not
  // determine it (transient auth-DB failure during serialization). The store
  // treats null as "no information" and keeps the last known value.
  has_password: z.boolean().nullable().optional().default(false),
  // Policy axis independent of has_password (#3886): whether this account is
  // permitted to hold a local password. false only when SSO is enforced
  // (app-level restrict_to='sso' or per-domain enforce_sso_only) or auth mode
  // is not 'full'. Defaults true so consumer accounts keep the affordance.
  password_auth_permitted: z.boolean().default(true),
  custid: z.string().default(''),
  cust: customerCanonical.nullable().default(null),
  email: z.string().default(''),
  // customer_since: formatted date string (e.g., "Mar 21, 2026") from Ruby epochdom()
  customer_since: z.string().optional(),

  // ─────────────────────────────────────────────────────────────────────────────
  // DomainSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  baseuri: z.string().default(''),
  canonical_domain: z.string().default(''),
  // Resolved link pool for the domain-context picker (#4063). Contract is
  // Array<String>, never null and never absent from a booted server: the
  // serializer's output_template seeds `[]` and DomainStrategy.link_domains
  // resolves an unset LINK_DOMAINS to [canonical_domain] server-side.
  //
  // `.default([])` — NOT `.nullable()`, and NOT `.optional()`:
  //  - a Zod default fires only for `undefined`, so an explicit `null` from a
  //    hypothetical nil-valued key would be a parse error, not a default.
  //    That is deliberate: it makes a Ruby-side regression loud.
  //  - `.optional()` would leave the key out of `bootstrapSchema.parse({})`,
  //    which is where the store's state shape comes from (bootstrapStore.ts:30),
  //    so Pinia would not track it reactively.
  //
  // `[]` therefore means exactly one thing to consumers: a stale pre-#4063
  // server (field absent). useDomainContext maps that back to
  // [canonicalDomain]. The frontend must never re-derive the unset case
  // itself — the server already resolved it.
  //
  // Values are normalized server-side (lowercased, port-stripped), so they
  // compare directly against `custom_domains` display_domain strings.
  // `canonical_domain` is NOT guaranteed to be a member: the canonical host
  // may be an internal platform address the picker deliberately hides.
  link_domains: z.array(z.string()).default([]),
  custom_domains: z.array(z.string()).optional().default([]),
  display_domain: z.string().default(''),
  domain_branding: brandSettingsCanonical.nullable().default(null),
  domain_context: z.string().nullish().default(null),
  homepage_config: homepageConfigCanonical.nullable().default(null),
  domain_id: z.string().default(''),
  domain_locale: z.string().nullable().default(null),
  domain_logo: z.string().nullable().default(null),
  domain_strategy: domainStrategySchema.default('canonical'),

  // ─────────────────────────────────────────────────────────────────────────────
  // I18nSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  locale: z.string().default('en'),
  default_locale: z.string().default('en'),
  fallback_locale: z.string().default('en'),
  supported_locales: z.array(z.string()).default([]),
  i18n_enabled: z.boolean().default(true),
  // Date/time display format: 'locale', 'iso8601', 'us', 'eu', 'eu-dot', 'uk',
  // 'long', or a date-fns pattern
  date_format: z.string().default('locale'),
  datetime_format: z.string().default('locale'),

  // ─────────────────────────────────────────────────────────────────────────────
  // MessagesSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  messages: z.array(messageSchema).nullable().default([]),
  global_banner: z.string().nullable().default(null),
  // Audience scope for the global broadcast banner. Consumed by BaseLayout to
  // decide which page audiences (and whether custom domains) see the banner.
  // Mirrors Onetime::Operations::BannerState::VALID_SCOPES. Default 'no_recipient'
  // keeps legacy string-only banners off recipient pages and custom domains.
  global_banner_scope: z
    .enum(['all', 'no_recipient', 'workspace'])
    .nullable()
    .default('no_recipient'),

  // ─────────────────────────────────────────────────────────────────────────────
  // SystemSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  ot_version: z.string().default(''),
  ot_version_long: z.string().default(''),
  ruby_version: z.string().default(''),
  shrimp: z.string().default(''),
  nonce: z.string().nullable().default(null),
  homepage_mode: z.string().nullable().default(null),
  enjoyTheVue: z.boolean().default(false),

  // ─────────────────────────────────────────────────────────────────────────────
  // OrganizationSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  organization: organizationSchema.optional(),

  // ─────────────────────────────────────────────────────────────────────────────
  // DiagnosticsSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  // Privacy-preserving actor identity for Sentry. ABSENT (not empty, not null)
  // for anonymous sessions — see diagnosticsActorSchema above for the full boundary
  // rationale and for why the inner object is strict rather than passthrough.
  diagnostics_actor: diagnosticsActorSchema.optional(),

  // ─────────────────────────────────────────────────────────────────────────────
  // Billing/Stripe fields
  // ─────────────────────────────────────────────────────────────────────────────
  stripe_customer: z.custom<Stripe.Customer>().optional(),
  stripe_subscriptions: z.array(z.custom<Stripe.Subscription>()).optional(),

  // ─────────────────────────────────────────────────────────────────────────────
  // Entitlement test mode (colonel only)
  // ─────────────────────────────────────────────────────────────────────────────
  entitlement_preview_planid: z.string().nullish(),
  entitlement_preview_plan_name: z.string().nullish(),

  // ─────────────────────────────────────────────────────────────────────────────
  // Development (always emitted by ConfigSerializer)
  // ─────────────────────────────────────────────────────────────────────────────
  development: developmentConfigSchema.default(developmentConfigSchema.parse({})),
});

// ═══════════════════════════════════════════════════════════════════════════════
// BOOTSTRAP PAYLOAD TYPE
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * BootstrapPayload - the contract type for window.__BOOTSTRAP_ME__.
 *
 * Derived directly from the schema. All nested types are canonical contracts.
 */
export type BootstrapPayload = z.infer<typeof bootstrapSchema>;

/** Input type before defaults are applied. */
export type BootstrapPayloadInput = z.input<typeof bootstrapSchema>;

// Default export for Rhales tsx import mode
export default bootstrapSchema;
