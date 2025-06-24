// src/schemas/config/settings.ts

import { z } from 'zod/v4';

const nullableString = z.string().nullable().optional();

/**
 * Rate Limits Management:
 *
 * Adding: Add new key with z.number().optional() in
 * appropriate comment group
 * Removing: Delete the line (catchall handles unknown keys gracefully)
 * Updating: Modify the key name directly
 *
 * All rate limit values are optional numeric limits (requests per time
 * window). Unknown rate limits are automatically handled via catchall for
 * backward compatibility.
 */
const RATE_LIMIT_KEYS = [
  // Core authentication and account operations
  'create_account',
  'update_account',
  'destroy_account',
  'authenticate_session',
  'destroy_session',
  'show_account',

  // Secret operations
  'create_secret',
  'show_secret',
  'show_metadata',
  'burn_secret',
  'attempt_secret_access',
  'failed_passphrase',

  // Domain operations
  'add_domain',
  'remove_domain',
  'list_domains',
  'get_domain',
  'verify_domain',
  'get_domain_brand',
  'get_domain_logo',
  'remove_domain_logo',
  'update_domain_brand',

  // Communication and feedback
  'email_recipient',
  'send_feedback',

  // Password reset operations
  'forgot_password_request',
  'forgot_password_reset',

  // Dashboard and UI operations
  'dashboard',
  'get_page',
  'get_image',

  // API and system operations
  'generate_apitoken',
  'check_status',
  'report_exception',
  'update_branding',
  'update_mutable_settings',
  'view_colonel',
  'external_redirect',

  // Payment operations
  'stripe_webhook',
] as const;

const rateLimitValue = z.number().optional();

const createRateLimitFields = () => {
  const fields: Record<string, typeof rateLimitValue> = {};

  // Add all defined rate limits
  RATE_LIMIT_KEYS.forEach((key) => {
    fields[key] = rateLimitValue;
  });

  return fields;
};

// --- Schemas for mutable_settings.defaults.yaml (Dynamic Settings) ---

const userInterfaceLogoSchema = z.object({
  url: z.string().optional(),
  alt: z.string().optional(),
  href: z.string().optional(), // Changed from link_to, matches YAML
});

const userInterfaceHeaderBrandingSchema = z.object({
  logo: userInterfaceLogoSchema.optional(),
  site_name: z.string().optional(),
});

const userInterfaceHeaderNavigationSchema = z.object({
  // Adjusted based on YAML <%= ... != 'false' %>
  enabled: z.boolean().optional(),
});

const userInterfaceHeaderSchema = z.object({
  enabled: z.boolean().optional(),
  branding: userInterfaceHeaderBrandingSchema.optional(),
  navigation: userInterfaceHeaderNavigationSchema.optional(),
});

const userInterfaceFooterLinkSchema = z.object({
  text: z.string().optional(),
  i18n_key: z.string().optional(),
  url: nullableString, // Can be nil from ENV
  external: z.boolean().optional(),
  icon: z.string().optional(), // Added
});

const userInterfaceFooterGroupSchema = z.object({
  // YAML :name:
  name: z.string().optional(),
  i18n_key: z.string().optional(),
  links: z.array(userInterfaceFooterLinkSchema).optional(),
});

const userInterfaceFooterLinksSchema = z.object({
  enabled: z.boolean().optional(),
  groups: z.array(userInterfaceFooterGroupSchema).optional(),
});

const userInterfaceSchema = z.object({
  enabled: z.boolean().optional(),
  header: userInterfaceHeaderSchema.optional(),
  footer_links: userInterfaceFooterLinksSchema.optional(),
  signup: z.boolean().optional(), // Added
  signin: z.boolean().optional(), // Added
  autoverify: z.null().optional(), // Added, YAML has 'null'
});

const apiSchema = z.object({
  enabled: z.boolean().default(true),
});

const secretOptionsSchema = z.object({
  // Can be nil from ENV
  default_ttl: z.number().nullable().optional(),
  ttl_options: z
    .union([z.string(), z.array(z.number())])
    .nullable()
    .optional(), // Can be nil from ENV
});

const featuresIncomingSchema = z.object({
  enabled: z.boolean().optional(),
  email: z.email().optional(),
  passphrase: z.string().optional(),
  regex: z.string().optional(),
});

const featuresStathatSchema = z.object({
  enabled: z.boolean().optional(),
  apikey: z.string().optional(),
  default_chart: z.string().optional(),
});

const featuresRegionJurisdictionIconSchema = z.object({
  collection: z.string().optional(),
  name: z.string().optional(),
});

const featuresRegionJurisdictionSchema = z.object({
  identifier: z.string().optional(),
  display_name: z.string().optional(),
  domain: z.string().optional(),
  icon: featuresRegionJurisdictionIconSchema.optional(),
});

const featuresRegionsSchema = z.object({
  // YAML: <%= ENV['REGIONS_ENABLED'] || true %>
  enabled: z.boolean().optional(),
  current_jurisdiction: nullableString,
  jurisdictions: z.array(featuresRegionJurisdictionSchema).optional(),
});

const featuresPlansPaymentLinksDetailSchema = z.object({
  tierid: z.string().optional(),
  month: nullableString,
  year: nullableString,
});

const featuresPlansPaymentLinksSchema = z.object({
  identity: featuresPlansPaymentLinksDetailSchema.optional(),
  dedicated: featuresPlansPaymentLinksDetailSchema.optional(),
});

const featuresPlansSchema = z.object({
  // YAML: <%= ENV['PLANS_ENABLED'] == 'true' || false %>
  enabled: z.boolean().optional(),
  stripe_key: nullableString,
  webook_signing_secret: z.string().optional(), // Typo 'webook' from YAML
  payment_links: featuresPlansPaymentLinksSchema.optional(),
});

const featuresDomainsClusterSchema = z.object({
  type: nullableString,
  api_key: nullableString,
  cluster_ip: nullableString,
  cluster_host: nullableString,
  cluster_name: nullableString,
  vhost_target: nullableString,
});

const featuresDomainsSchema = z.object({
  // YAML: <%= ENV['DOMAINS_ENABLED'] || true %>
  enabled: z.boolean().optional(),
  default: nullableString,
  cluster: featuresDomainsClusterSchema.optional(),
});

const featuresSchema = z.object({
  incoming: featuresIncomingSchema.optional(),
  stathat: featuresStathatSchema.optional(),
  regions: featuresRegionsSchema.optional(),
  plans: featuresPlansSchema.optional(),
  domains: featuresDomainsSchema.optional(),
});

const diagnosticsSentryDefaultsSchema = z.object({
  dsn: nullableString,
  sampleRate: z.number().optional(),
  maxBreadcrumbs: z.number().optional(),
  logErrors: z.boolean().optional(),
});

const diagnosticsSentryBackendSchema = diagnosticsSentryDefaultsSchema.extend({});

const diagnosticsSentryFrontendSchema = diagnosticsSentryDefaultsSchema.extend({
  trackComponents: z.boolean().optional(),
});

const diagnosticsSentrySchema = z.object({
  defaults: diagnosticsSentryDefaultsSchema.optional(),
  backend: diagnosticsSentryBackendSchema.optional(),
  frontend: diagnosticsSentryFrontendSchema.optional(),
});

const diagnosticsSchema = z.object({
  enabled: z.boolean().default(false),
  sentry: diagnosticsSentrySchema.optional(),
});

const limitsSchema = z.object(createRateLimitFields()).catchall(rateLimitValue);

const mailValidationSchema = z.object({
  default_validation_type: z.string().default('mx'),
  verifier_email: z.email().default('support@onetimesecret.dev'),
  verifier_domain: z.string().default('onetimesecret.dev'),
  connection_timeout: z.number().optional(),
  response_timeout: z.number().optional(),
  connection_attempts: z.number().optional(),
  allowed_domains_only: z.boolean().optional(),
  allowed_emails: z.array(z.string()).optional(),
  blocked_emails: z.array(z.string()).optional(),
  allowed_domains: z.array(z.string()).optional(),
  blocked_domains: z.array(z.string()).optional(),
  blocked_mx_ip_addresses: z.array(z.string()).optional(),
  dns: z.array(z.string()).optional(),
  smtp_port: z.number().optional(),
  smtp_fail_fast: z.boolean().optional(),
  smtp_safe_check: z.boolean().optional(),
  not_rfc_mx_lookup_flow: z.boolean().optional(),
  logger: z
    .object({
      tracking_event: z.string().default('all'),
      stdout: z.boolean().default(true),
      log_absolute_path: z.string().optional(),
    })
    .optional(),
});

const dynamicMailValidationSchema = z.object({
  recipients: mailValidationSchema.optional(),
  accounts: mailValidationSchema.optional(),
});

const dynamicMailSchema = z.object({
  validation: dynamicMailValidationSchema.optional(),
});

export const mutableSettingsSchema = z.object({
  user_interface: userInterfaceSchema.optional(), // Renamed from interface
  api: apiSchema.optional(),
  secret_options: secretOptionsSchema.optional(),
  features: featuresSchema.optional(),
  limits: limitsSchema.optional(),
  mail: dynamicMailSchema.optional(), // Updated mail schema
});

export const mutableSettingsDetailsSchema = mutableSettingsSchema.extend({});
export type MutableSettingsDetails = z.infer<typeof mutableSettingsDetailsSchema>;

// --- Schemas for config.yaml (Static Settings) ---

const staticSiteAuthenticationSchema = z.object({
  enabled: z.boolean().default(false),
  colonels: z.array(z.string()).default([]),
});

const staticSiteAuthenticitySchema = z.object({
  enabled: z.boolean().default(false),
  type: z.string().optional(),
  secret_key: z.string().optional(),
});

const staticSiteMiddlewareSchema = z.object({
  static_files: z.boolean().default(true),
  utf8_sanitizer: z.boolean().default(true),
  http_origin: z.boolean().optional(),
  escaped_params: z.boolean().optional(),
  xss_header: z.boolean().optional(),
  frame_options: z.boolean().optional(),
  path_traversal: z.boolean().optional(),
  cookie_tossing: z.boolean().optional(),
  ip_spoofing: z.boolean().optional(),
  strict_transport: z.boolean().optional(),
});

const staticSiteSchema = z.object({
  host: z.string().default('localhost:3000'),
  ssl: z.boolean().default(false),
  secret: z.string().default('CHANGEME'),
  authentication: staticSiteAuthenticationSchema,
  authenticity: staticSiteAuthenticitySchema,
  middleware: staticSiteMiddlewareSchema,
});

const staticStorageDbConnectionSchema = z.object({
  url: z.string().default('redis://localhost:6379'),
});

// 'connection' is required for 'db' (if 'db' exists and is not optional
// itself)
const staticStorageDbSchema = z.object({
  // Ensure connection object is created by default
  connection: staticStorageDbConnectionSchema,
  // Allow null for database_mapping values
  database_mapping: z.record(z.string(), z.number().nullable()).optional(),
});

/**
 * Storage Database Schema Configuration
 *
 * The 'db' property within 'storage' is configured as optional based on the current
 * JSON schema specification. This design decision reflects the following considerations:
 *
 * Schema Requirements Analysis:
 * - The JSON schema does not include 'db' in storage.required array
 * - Therefore 'db' remains optional at the storage level
 *
 * Default Value Behavior:
 * - If 'db' is present: Internal .default({}) for 'connection' applies automatically
 * - If 'db' is absent: No database configuration is generated
 *
 * Alternative Implementation:
 * If the schema required 'db' to always exist when 'storage' is present:
 * ```
 * db: staticStorageDbSchema.default({})
 * ```
 *
 * Current Implementation Rationale:
 * Maintains schema compliance while allowing flexible storage configurations.
 * The Ruby default generator will only create database configuration when
 * explicitly specified, preventing unnecessary Redis connection attempts.
 */
const staticStorageSchema = z.object({
  // Kept optional per existing JSON schema. If db were required for storage,
  // it would need .default({})
  db: staticStorageDbSchema.optional(),
});

const staticMailConnectionSchema = z.object({
  mode: z.string().default('smtp'),
  auth: z.string().default('login'),
  region: z.string().optional(),
  from: z.email().optional().default('noreply@example.com'),
  fromname: z.string().default('OneTimeSecret'),
  host: z.string().optional(),
  port: z.number().optional(),
  user: nullableString,
  pass: nullableString,
  tls: z.boolean().nullable().optional(),
});

// The 'defaults' property within 'validation' is an object type is
// the same shape as recipient and accounts fields.
const staticMailIndividualValidationSchema = mailValidationSchema; // Alias for clarity

// 'validation' itself is a required property of 'mail'.
// The 'defaults' property *within* 'validation' is optional.
// So staticMailValidationSchema refers to the structure for mail.validation.
const staticMailValidationSchema = z.object({
  defaults: staticMailIndividualValidationSchema.optional(), // 'defaults' key is optional
});

// 'connection' and 'validation' are required for 'mail'
const staticMailSchema = z.object({
  connection: staticMailConnectionSchema, // Ensure connection object is created
  validation: staticMailValidationSchema, // Ensure validation object is created
});

const staticLoggingSchema = z.object({
  http_requests: z.boolean().default(true),
});

const staticI18nSchema = z.object({
  enabled: z.boolean().default(false),
  default_locale: z.string().default('en'),
  fallback_locale: z.record(z.string(), z.union([z.array(z.string()), z.string()])),
  locales: z.array(z.string()).default([]),
  incomplete: z.array(z.string()).default([]),
});

const staticDevelopmentSchema = z.object({
  enabled: z.boolean().optional(),
  debug: z.boolean().optional(),
  frontend_host: z.string().optional(),
});

const staticExperimentalSchema = z.object({
  allow_nil_global_secret: z.boolean().default(false),
  rotated_secrets: z.array(z.string()).default([]),
  freeze_app: z.boolean().default(false),
});

export const staticConfigSchema = z.object({
  site: staticSiteSchema,
  storage: staticStorageSchema, // storage itself gets a default empty object
  mail: staticMailSchema,
  logging: staticLoggingSchema,
  diagnostics: diagnosticsSchema.optional(),
  i18n: staticI18nSchema,
  development: staticDevelopmentSchema,
  experimental: staticExperimentalSchema,
});

export type StaticConfig = z.infer<typeof staticConfigSchema>;

// Rate limit types for better type safety
export type RateLimitKey = (typeof RATE_LIMIT_KEYS)[number] | string;
export type RateLimits = z.infer<typeof limitsSchema>;
export { RATE_LIMIT_KEYS };
