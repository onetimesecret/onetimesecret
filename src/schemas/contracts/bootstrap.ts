// src/schemas/contracts/bootstrap.ts
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
import { regionsConfigSchema } from '@/schemas/contracts/config/section/jurisdiction';
import { brandSettingsCanonical } from '@/schemas/contracts/custom-domain';
import { customerCanonical } from '@/schemas/contracts/customer';

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
  external: z.boolean().optional(),
  icon: z.string().optional(),
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

export const headerLogoSchema = z.object({
  url: z.string().default(''),
  alt: z.string().default(''),
  link_to: z.string().default('/'),
});

export const headerBrandingSchema = z.object({
  logo: headerLogoSchema.default(headerLogoSchema.parse({})),
  site_name: z.string().optional(),
});

export const headerNavigationSchema = z.object({
  enabled: z.boolean().default(true),
});

export const headerConfigSchema = z.object({
  enabled: z.boolean().default(true),
  branding: headerBrandingSchema.optional(),
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
 * // Full configuration with custom branding and footer links
 * const ui = {
 *   enabled: true,
 *   header: {
 *     enabled: true,
 *     branding: {
 *       logo: { url: '/images/logo.svg', alt: 'Company Logo', link_to: '/' },
 *       site_name: 'My Secret Sharing App',
 *     },
 *     navigation: { enabled: true },
 *   },
 *   footer_links: {
 *     enabled: true,
 *     groups: [
 *       {
 *         name: 'workspace',
 *         links: [
 *           { text: 'API Docs', url: 'https://docs.example.com/api', external: true },
 *           { i18n_key: 'web.footer.privacy', url: '/privacy' },
 *         ],
 *       },
 *     ],
 *   },
 * };
 */
export const uiInterfaceSchema = z.object({
  enabled: z.boolean().default(true),
  header: headerConfigSchema.optional(),
  footer_links: footerLinksConfigSchema.optional(),
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

export const authenticationSettingsSchema = authenticationSettingsInner.nullable();

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
});

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURES SCHEMA
// ═══════════════════════════════════════════════════════════════════════════════

export const featuresSchema = z.object({
  markdown: z.boolean().default(false),
  mfa: z.boolean().optional(),
  lockout: z.boolean().optional(),
  password_requirements: z.boolean().optional(),
  email_auth: z.boolean().optional(),
  webauthn: z.boolean().optional(),
  sso: z.union([z.boolean(), ssoConfigSchema]).optional(),
  sso_only: z.boolean().optional(),
  magic_links: z.boolean().optional(),
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
  minimum_length: z.number().int().min(1).max(256).default(8),
  maximum_length: z.number().int().min(8).max(1024).default(128),
  enforce_complexity: z.boolean().default(false),
});

/**
 * Canonical secret options schema for bootstrap payload.
 * No transforms - Ruby serializers send already-typed data.
 */
export const secretOptionsSchema = z.object({
  default_ttl: z.number().int().positive().default(604800),
  ttl_options: z
    .array(z.number().int().positive().min(60).max(2592000))
    .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),
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
  tracesSampleRate: z.number().optional(),
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
 */
export const organizationSchema = z
  .object({
    id: z.string(),
    extid: z.string(),
    display_name: z.string(),
    is_default: z.boolean(),
    planid: z.string().nullish(),
    current_user_role: z.enum(['owner', 'admin', 'member']).nullish(),
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
export type HeaderLogo = z.infer<typeof headerLogoSchema>;
export type HeaderBranding = z.infer<typeof headerBrandingSchema>;
export type HeaderNavigation = z.infer<typeof headerNavigationSchema>;
export type HeaderConfig = z.infer<typeof headerConfigSchema>;
export type UiInterface = z.infer<typeof uiInterfaceSchema>;
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
 */
export const bootstrapSchema = z.object({
  // ─────────────────────────────────────────────────────────────────────────────
  // ConfigSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  authentication: authenticationSettingsSchema.default(authenticationSettingsInner.parse({})),
  d9s_enabled: z.boolean().default(false),
  diagnostics: diagnosticsSchema.default(diagnosticsInner.parse({})),
  domains_enabled: z.boolean().default(false),
  features: featuresSchema.default(featuresSchema.parse({})),
  frontend_development: z.boolean().default(false),
  frontend_host: z.string().default(''),
  billing_enabled: z.boolean().default(false),
  regions: regionsConfigSchema.optional(),
  regions_enabled: z.boolean().default(false),
  secret_options: secretOptionsSchema.default(secretOptionsSchema.parse({})),
  site_host: z.string().default(''),
  support_host: z.string().default(''),
  ui: uiInterfaceSchema.default(uiInterfaceSchema.parse({})),
  available_jurisdictions: z.array(z.string()).default([]),

  // ─────────────────────────────────────────────────────────────────────────────
  // AuthenticationSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  apitoken: z.string().optional(),
  authenticated: z.boolean().default(false),
  awaiting_mfa: z.boolean().optional().default(false),
  had_valid_session: z.boolean().default(false),
  has_password: z.boolean().optional().default(false),
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
  custom_domains: z.array(z.string()).optional().default([]),
  display_domain: z.string().default(''),
  domain_branding: brandSettingsCanonical.nullable().default(null),
  domain_context: z.string().nullish().default(null),
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
  // Date/time display format: 'locale', 'iso8601', 'us', 'eu', 'eu-dot', 'uk', 'long', or date-fns pattern
  date_format: z.string().default('locale'),
  datetime_format: z.string().default('locale'),

  // ─────────────────────────────────────────────────────────────────────────────
  // MessagesSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  messages: z.array(messageSchema).nullable().default([]),
  global_banner: z.string().nullable().default(null),

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
  // Billing/Stripe fields
  // ─────────────────────────────────────────────────────────────────────────────
  stripe_customer: z.custom<Stripe.Customer>().optional(),
  stripe_subscriptions: z.array(z.custom<Stripe.Subscription>()).optional(),

  // ─────────────────────────────────────────────────────────────────────────────
  // Entitlement test mode (colonel only)
  // ─────────────────────────────────────────────────────────────────────────────
  entitlement_test_planid: z.string().nullish(),
  entitlement_test_plan_name: z.string().nullish(),

  // ─────────────────────────────────────────────────────────────────────────────
  // Development
  // ─────────────────────────────────────────────────────────────────────────────
  development: developmentConfigSchema.optional(),
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
