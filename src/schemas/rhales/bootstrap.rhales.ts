// src/schemas/rhales/bootstrap.rhales.ts
//
// Rhales-compatible Zod schema for bootstrap payload validation.
//
// This schema defines the contract for window.__BOOTSTRAP_STATE__ data
// injected by the Ruby backend. Rhales uses this for server-side validation
// to ensure data matches the expected shape before hydration.
//
// SSOT Principle:
// - This file is the single source of truth for bootstrap structure
// - Rhales reads this via <schema src="..."> in index.rue
// - Frontend types are derived from bootstrap.d.ts which aligns with this schema
// - Ruby serializers must produce data matching this schema
//
// After modifying this schema, run: `pnpm run build:schemas` to regenerate
// the JSON schemas used by Rhales middleware.

import { z } from 'zod';

// ═══════════════════════════════════════════════════════════════════════════════
// LOCALE & MESSAGES
// ═══════════════════════════════════════════════════════════════════════════════

const messageSchema = z.object({
  type: z.string(),
  content: z.string(),
});

// ═══════════════════════════════════════════════════════════════════════════════
// AUTHENTICATION
// ═══════════════════════════════════════════════════════════════════════════════

const authenticationSchema = z.object({
  enabled: z.boolean(),
  signup: z.boolean(),
  signin: z.boolean(),
  autoverify: z.boolean(),
  required: z.boolean(),
  mode: z.enum(['simple', 'full']).optional(),
}).nullable();

// ═══════════════════════════════════════════════════════════════════════════════
// DIAGNOSTICS & DEVELOPMENT
// ═══════════════════════════════════════════════════════════════════════════════

const diagnosticsSchema = z.object({
  sentry: z.object({}).optional(),
}).nullable();

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURES
// ═══════════════════════════════════════════════════════════════════════════════

const featuresSchema = z.object({
  magic_links: z.boolean(),
  email_auth: z.boolean(),
  webauthn: z.boolean(),
});

// ═══════════════════════════════════════════════════════════════════════════════
// BOOTSTRAP SCHEMA (main export)
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
const schema = z.object({
  // ─────────────────────────────────────────────────────────────────────────────
  // ConfigSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  authentication: authenticationSchema,
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
  ui: z.object({}),

  // ─────────────────────────────────────────────────────────────────────────────
  // AuthenticationSerializer fields
  // ─────────────────────────────────────────────────────────────────────────────
  authenticated: z.boolean(),
  awaiting_mfa: z.boolean().optional(),
  had_valid_session: z.boolean(),
  custid: z.string().nullable(),
  cust: z.object({}),
  email: z.string().nullable(),
  customer_since: z.number().nullable(),

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

  // Note: page_title, description, keywords, baseuri, no_cache, and vite_assets_html
  // are template-only props and not included in window.__BOOTSTRAP_STATE__
});

// Default export required for Rhales tsx import mode
export default schema;

// Named export for TypeScript type inference
export { schema };
export type BootstrapPayload = z.infer<typeof schema>;
