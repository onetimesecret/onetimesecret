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
  url: z.string(),
  alt: z.string(),
  link_to: z.string(),
});

export const headerBrandingSchema = z.object({
  logo: headerLogoSchema,
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

export const uiInterfaceSchema = z.object({
  enabled: z.boolean().default(true),
  header: headerConfigSchema.optional(),
  footer_links: footerLinksConfigSchema.optional(),
});

// ═══════════════════════════════════════════════════════════════════════════════
// AUTHENTICATION SCHEMAS
// ═══════════════════════════════════════════════════════════════════════════════

export const authenticationSettingsSchema = z
  .object({
    enabled: z.boolean(),
    signup: z.boolean(),
    signin: z.boolean(),
    autoverify: z.boolean(),
    required: z.boolean(),
    mode: z.enum(['simple', 'full']).optional(),
  })
  .nullable();

// ═══════════════════════════════════════════════════════════════════════════════
// SSO SCHEMAS
// ═══════════════════════════════════════════════════════════════════════════════

export const ssoProviderSchema = z.object({
  route_name: z.string(),
  display_name: z.string(),
});

export const ssoConfigSchema = z.object({
  enabled: z.boolean(),
  providers: z.array(ssoProviderSchema).optional(),
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
 * Diagnostics configuration for bootstrap payload.
 */
export const diagnosticsSchema = z
  .object({
    sentry: sentryConfigSchema.optional(),
  })
  .nullable();

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
  authentication: authenticationSettingsSchema,
  d9s_enabled: z.boolean(),
  diagnostics: diagnosticsSchema,
  domains_enabled: z.boolean(),
  features: featuresSchema,
  frontend_development: z.boolean(),
  frontend_host: z.string(),
  billing_enabled: z.boolean(),
  regions: regionsConfigSchema.optional(),
  regions_enabled: z.boolean(),
  secret_options: secretOptionsSchema,
  site_host: z.string(),
  support_host: z.string(),
  ui: uiInterfaceSchema,
  available_jurisdictions: z.array(z.string()),

  // ─────────────────────────────────────────────────────────────────────────────
  // AuthenticationSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  apitoken: z.string().optional(),
  authenticated: z.boolean(),
  awaiting_mfa: z.boolean().optional(),
  had_valid_session: z.boolean(),
  has_password: z.boolean().optional(),
  custid: z.string(),
  cust: customerCanonical.nullable(),
  email: z.string(),
  // customer_since: formatted date string (e.g., "Mar 21, 2026") from Ruby epochdom()
  customer_since: z.string().optional(),

  // ─────────────────────────────────────────────────────────────────────────────
  // DomainSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  baseuri: z.string(),
  canonical_domain: z.string(),
  custom_domains: z.array(z.string()).optional(),
  display_domain: z.string(),
  domain_branding: brandSettingsCanonical.nullable(),
  domain_context: z.string().nullish(),
  domain_id: z.string(),
  domain_locale: z.string().nullable(),
  domain_logo: z.string().nullable(),
  domain_strategy: domainStrategySchema,

  // ─────────────────────────────────────────────────────────────────────────────
  // I18nSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  locale: z.string(),
  default_locale: z.string(),
  fallback_locale: z.string(),
  supported_locales: z.array(z.string()),
  i18n_enabled: z.boolean(),

  // ─────────────────────────────────────────────────────────────────────────────
  // MessagesSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  messages: z.array(messageSchema).nullable(),
  global_banner: z.string().nullable(),

  // ─────────────────────────────────────────────────────────────────────────────
  // SystemSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  ot_version: z.string(),
  ot_version_long: z.string(),
  ruby_version: z.string(),
  shrimp: z.string(),
  nonce: z.string().nullable(),
  homepage_mode: z.string().nullable(),
  enjoyTheVue: z.boolean(),

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
