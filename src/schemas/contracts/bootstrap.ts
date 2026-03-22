// src/schemas/contracts/bootstrap.ts
//
// Single source of truth for bootstrap payload schema.
//
// This schema defines the contract for window.__BOOTSTRAP_STATE__ data
// injected by the Ruby backend. It is used by:
// - Rhales for server-side validation (via <schema src="..."> in index.rue)
// - TypeScript for client-side type inference
// - Contract tests to ensure Ruby serializers match this schema
//
// After modifying this schema, run: `pnpm run build:schemas` to regenerate
// the JSON schemas used by Rhales middleware.

import { z } from 'zod';

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
// DIAGNOSTICS SCHEMA
// ═══════════════════════════════════════════════════════════════════════════════

export const diagnosticsSchema = z
  .object({
    sentry: z.object({}).optional(),
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
// EXPORTED TYPES (derived from sub-schemas)
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

// ═══════════════════════════════════════════════════════════════════════════════
// BOOTSTRAP PAYLOAD SCHEMA (full payload for Rhales validation)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Bootstrap payload schema for window.__BOOTSTRAP_STATE__.
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
  d9s_enabled: z.boolean().nullable(),
  diagnostics: diagnosticsSchema,
  domains: z.object({}).optional(),
  domains_enabled: z.boolean(),
  features: featuresSchema,
  frontend_development: z.boolean(),
  frontend_host: z.string(),
  billing_enabled: z.boolean(),
  regions: z.object({}).optional(),
  regions_enabled: z.boolean(),
  secret_options: z.object({}),
  site_host: z.string(),
  ui: uiInterfaceSchema,

  // ─────────────────────────────────────────────────────────────────────────────
  // AuthenticationSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  authenticated: z.boolean(),
  awaiting_mfa: z.boolean().optional(),
  had_valid_session: z.boolean(),
  custid: z.string().nullable(),
  cust: z.object({}).nullable(),
  email: z.string().nullable(),
  // customer_since: formatted date string (e.g., "Mar 21, 2026") from Ruby epochdom()
  customer_since: z.string().nullable(),

  // ─────────────────────────────────────────────────────────────────────────────
  // DomainSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  canonical_domain: z.string().nullable(),
  custom_domains: z.array(z.string()).nullable(),
  display_domain: z.string().nullable(),
  domain_branding: z.object({}).nullable(),
  domain_id: z.string().nullable(),
  domain_locale: z.string().nullable(),
  domain_logo: z.object({}).nullable(),
  domain_strategy: z.string().nullable(),

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
  shrimp: z.string().nullable(),
  nonce: z.string().nullable(),
  homepage_mode: z.string().nullable(),

  // ─────────────────────────────────────────────────────────────────────────────
  // OrganizationSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  organization: organizationSchema.optional(),

  // ─────────────────────────────────────────────────────────────────────────────
  // Development
  // ─────────────────────────────────────────────────────────────────────────────
  development: developmentConfigSchema.optional(),

  // Note: page_title, description, keywords, baseuri, no_cache, and vite_assets_html
  // are template-only props and not included in window.__BOOTSTRAP_STATE__
});

// ═══════════════════════════════════════════════════════════════════════════════
// PARTIAL SCHEMA FOR UI VALIDATION
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Partial schema for validating UI-specific portions of bootstrap.
 * Used by frontend code that only needs UI fields.
 */
export const bootstrapUiSchema = z.object({
  ui: uiInterfaceSchema.default({ enabled: true }),
  messages: z.array(messageSchema).default([]),
  features: featuresSchema.default({ markdown: false }),
  development: developmentConfigSchema.optional(),
  organization: organizationSchema.optional(),
  supported_locales: z.array(z.string()).default([]),
  default_locale: z.string().default('en'),
});

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════════════════════════

/** Parse UI portions of bootstrap payload with defaults. */
export function parseBootstrapUi(data: unknown) {
  return bootstrapUiSchema.parse(data);
}

/** Default values for UI portions of bootstrap. */
export const BOOTSTRAP_UI_DEFAULTS = bootstrapUiSchema.parse({});

/** Full BootstrapPayload type for TypeScript. */
export type BootstrapPayload = z.infer<typeof bootstrapSchema>;

/** Input type before defaults are applied. */
export type BootstrapPayloadInput = z.input<typeof bootstrapSchema>;

// Default export for Rhales tsx import mode
export default bootstrapSchema;
