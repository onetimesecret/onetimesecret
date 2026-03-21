// src/schemas/bootstrap.schema.ts
//
// Zod schema for validating bootstrap payload at runtime.
//
// This schema validates the structure of window.__BOOTSTRAP_STATE__
// injected by the Ruby backend. It provides runtime validation and
// sensible defaults for anonymous/logged-out users.
//
// Type Strategy:
// - UI-specific types (Footer, Header, etc.) are defined here and exported
// - Shared types (Customer, BrandSettings, etc.) come from v2 shapes
// - The BootstrapPayload interface is maintained manually in bootstrap.d.ts
//   to ensure compatibility with existing v2 type imports

import { z } from 'zod';

// ═══════════════════════════════════════════════════════════════════════════════
// UI CONFIGURATION SCHEMAS (bootstrap-specific)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Locale info object with code, name, and enabled flag.
 * This is the structure returned by the server for supported_locales.
 */
export const localeInfoSchema = z.object({
  code: z.string(),
  name: z.string(),
  enabled: z.boolean().default(true),
});

/**
 * Flash message displayed to the user.
 */
export const messageSchema = z.object({
  type: z.enum(['success', 'error', 'info']),
  content: z.string(),
});

/**
 * Footer link configuration.
 */
export const footerLinkSchema = z.object({
  text: z.string().optional(),
  i18n_key: z.string().optional(),
  url: z.string(),
  external: z.boolean().optional(),
  icon: z.string().optional(),
});

/**
 * Footer group with links.
 */
export const footerGroupSchema = z.object({
  name: z.string().optional(),
  i18n_key: z.string().optional(),
  links: z.array(footerLinkSchema).default([]),
});

/**
 * Footer links configuration.
 */
export const footerLinksConfigSchema = z.object({
  enabled: z.boolean().default(false),
  groups: z.array(footerGroupSchema).default([]),
});

/**
 * Header logo configuration.
 */
export const headerLogoSchema = z.object({
  url: z.string(),
  alt: z.string(),
  link_to: z.string(),
});

/**
 * Header branding configuration.
 */
export const headerBrandingSchema = z.object({
  logo: headerLogoSchema,
  site_name: z.string().optional(),
});

/**
 * Header navigation configuration.
 */
export const headerNavigationSchema = z.object({
  enabled: z.boolean().default(true),
});

/**
 * Header configuration.
 */
export const headerConfigSchema = z.object({
  enabled: z.boolean().default(true),
  branding: headerBrandingSchema.optional(),
  navigation: headerNavigationSchema.optional(),
});

/**
 * UI interface configuration.
 */
export const uiInterfaceSchema = z.object({
  enabled: z.boolean().default(true),
  header: headerConfigSchema.optional(),
  footer_links: footerLinksConfigSchema.optional(),
});

/**
 * Development mode configuration.
 */
export const developmentConfigSchema = z.object({
  enabled: z.boolean().default(false),
  domain_context_enabled: z.boolean().default(false),
});

/**
 * SSO provider configuration.
 */
export const ssoProviderSchema = z.object({
  route_name: z.string(),
  display_name: z.string(),
});

/**
 * SSO configuration object (when SSO is enabled).
 */
export const ssoConfigSchema = z.object({
  enabled: z.boolean(),
  providers: z.array(ssoProviderSchema).optional(),
});

/**
 * Features configuration.
 */
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

/**
 * Organization record for authenticated users.
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
// EXPORTED TYPES (derived from schemas above)
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
export type DevelopmentConfig = z.infer<typeof developmentConfigSchema>;
export type SSOProvider = z.infer<typeof ssoProviderSchema>;
export type SSOConfig = z.infer<typeof ssoConfigSchema>;
export type Features = z.infer<typeof featuresSchema>;
export type Organization = z.infer<typeof organizationSchema>;

// ═══════════════════════════════════════════════════════════════════════════════
// BOOTSTRAP VALIDATION SCHEMA
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Partial bootstrap schema for runtime validation.
 *
 * This schema validates the UI-specific portions of the bootstrap payload.
 * For full payload validation, combine with the manual BootstrapPayload type.
 *
 * Note: This doesn't include Customer, BrandSettings, etc. because those
 * use complex transforms from v2 shapes that are validated elsewhere.
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

/**
 * Parse UI portions of bootstrap payload with defaults.
 */
export function parseBootstrapUi(data: unknown) {
  return bootstrapUiSchema.parse(data);
}

/**
 * Default values for UI portions of bootstrap.
 */
export const BOOTSTRAP_UI_DEFAULTS = bootstrapUiSchema.parse({});
