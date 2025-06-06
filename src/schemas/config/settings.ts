// src/schemas/config/settings.ts

import { transforms } from '@/schemas/transforms';
import { z } from 'zod/v4';

const nullableString = z.string().nullable().optional();

/**
 * Rate Limits Management:
 *
 * Adding: Add new key with transforms.fromString.number.optional() in appropriate comment group
 * Removing: Delete the line (catchall handles unknown keys gracefully)
 * Updating: Modify the key name directly
 *
 * All rate limit values are optional numeric limits (requests per time window).
 * Unknown rate limits are automatically handled via catchall for backward compatibility.
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
  'update_system_settings',
  'view_colonel',
  'external_redirect',

  // Payment operations
  'stripe_webhook',
] as const;

const rateLimitValue = transforms.fromString.number.optional();

const createRateLimitFields = () => {
  const fields: Record<string, typeof rateLimitValue> = {};

  // Add all defined rate limits
  RATE_LIMIT_KEYS.forEach((key) => {
    fields[key] = rateLimitValue;
  });

  return fields;
};

// --- Schemas for system_settings.defaults.yaml (Dynamic Settings) ---

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
  enabled: transforms.fromString.boolean.optional(),
});

const userInterfaceHeaderSchema = z.object({
  enabled: transforms.fromString.boolean.optional(),
  branding: userInterfaceHeaderBrandingSchema.optional(),
  navigation: userInterfaceHeaderNavigationSchema.optional(),
});

const userInterfaceFooterLinkSchema = z.object({
  text: z.string().optional(),
  i18n_key: z.string().optional(),
  url: nullableString, // Can be nil from ENV
  external: transforms.fromString.boolean.optional(),
  icon: z.string().optional(), // Added
});

const userInterfaceFooterGroupSchema = z.object({
  // YAML :name:
  name: z.string().optional(),
  i18n_key: z.string().optional(),
  links: z.array(userInterfaceFooterLinkSchema).optional(),
});

const userInterfaceFooterLinksSchema = z.object({
  enabled: transforms.fromString.boolean.optional(),
  groups: z.array(userInterfaceFooterGroupSchema).optional(),
});

const userInterfaceSchema = z.object({
  enabled: transforms.fromString.boolean.optional(),
  header: userInterfaceHeaderSchema.optional(),
  footer_links: userInterfaceFooterLinksSchema.optional(),
  signup: transforms.fromString.boolean.optional(), // Added
  signin: transforms.fromString.boolean.optional(), // Added
  autoverify: z.null().optional(), // Added, YAML has 'null'
});

const apiSchema = z.object({
  enabled: transforms.fromString.boolean.optional(),
});

const secretOptionsSchema = z.object({
  // Can be nil from ENV
  default_ttl: transforms.fromString.number.nullable().optional(),
  ttl_options: z
    .union([z.string(), z.array(transforms.fromString.number)])
    .nullable()
    .optional(), // Can be nil from ENV
});

const featuresIncomingSchema = z.object({
  enabled: transforms.fromString.boolean.optional(),
  email: transforms.fromString.optionalEmail,
  passphrase: z.string().optional(),
  regex: z.string().optional(),
});

const featuresStathatSchema = z.object({
  enabled: transforms.fromString.boolean.optional(),
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
  enabled: transforms.fromString.boolean.optional(),
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
  enabled: transforms.fromString.boolean.optional(),
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
  enabled: transforms.fromString.boolean.optional(),
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
  sampleRate: transforms.fromString.number.optional(),
  maxBreadcrumbs: transforms.fromString.number.optional(),
  logErrors: transforms.fromString.boolean.optional(),
});

const diagnosticsSentryBackendSchema = z.object({
  dsn: nullableString,
});

const diagnosticsSentryFrontendSchema = z.object({
  dsn: nullableString,
  trackComponents: transforms.fromString.boolean.optional(),
});

const diagnosticsSentrySchema = z.object({
  defaults: diagnosticsSentryDefaultsSchema.optional(),
  backend: diagnosticsSentryBackendSchema.optional(),
  frontend: diagnosticsSentryFrontendSchema.optional(),
});

const diagnosticsSchema = z.object({
  // YAML: <%= ENV['DIAGNOSTICS_ENABLED'] == 'true' || false %>
  enabled: transforms.fromString.boolean.optional(),
  sentry: diagnosticsSentrySchema.optional(),
});

const limitsSchema = z.object(createRateLimitFields()).catchall(rateLimitValue);

const individualMailValidationSchema = z.object({
  default_validation_type: z.string().optional(),
  verifier_email: transforms.fromString.optionalEmail,
  verifier_domain: z.string().optional(),
  connection_timeout: transforms.fromString.number.optional(),
  response_timeout: transforms.fromString.number.optional(),
  connection_attempts: transforms.fromString.number.optional(),
  allowed_domains_only: transforms.fromString.boolean.optional(),
  allowed_emails: z.array(z.string()).optional(),
  blocked_emails: z.array(z.string()).optional(),
  allowed_domains: z.array(z.string()).optional(),
  blocked_domains: z.array(z.string()).optional(),
  blocked_mx_ip_addresses: z.array(z.string()).optional(),
  dns: z.array(z.string()).optional(),
  smtp_port: transforms.fromString.number.optional(),
  smtp_fail_fast: transforms.fromString.boolean.optional(),
  smtp_safe_check: transforms.fromString.boolean.optional(),
  not_rfc_mx_lookup_flow: transforms.fromString.boolean.optional(),
  logger: z
    .object({
      // YAML :all
      tracking_event: z.string().optional(),
      stdout: transforms.fromString.boolean.optional(),
      log_absolute_path: z.string().optional(),
    })
    .optional(),
});

const dynamicMailValidationSchema = z.object({
  recipients: individualMailValidationSchema.optional(),
  accounts: individualMailValidationSchema.optional(),
});

const dynamicMailSchema = z.object({
  validation: dynamicMailValidationSchema.optional(),
});

export const systemSettingsSchema = z.object({
  user_interface: userInterfaceSchema.optional(), // Renamed from interface
  api: apiSchema.optional(),
  secret_options: secretOptionsSchema.optional(),
  features: featuresSchema.optional(),
  diagnostics: diagnosticsSchema.optional(),
  limits: limitsSchema.optional(),
  mail: dynamicMailSchema.optional(), // Updated mail schema
});

export const systemSettingsDetailsSchema = systemSettingsSchema.extend({});
export type SystemSettingsDetails = z.infer<typeof systemSettingsDetailsSchema>;

// --- Schemas for config.yaml (Static Settings) ---

const staticSiteAuthenticationSchema = z.object({
  enabled: transforms.fromString.boolean.optional(),
  colonels: z.array(z.string()).optional(),
});

const staticSiteAuthenticitySchema = z.object({
  type: z.string().optional(),
  secret_key: z.string().optional(),
});

const staticSiteMiddlewareSchema = z.object({
  static_files: transforms.fromString.boolean.optional(),
  utf8_sanitizer: transforms.fromString.boolean.optional(),
  http_origin: transforms.fromString.boolean.optional(),
  escaped_params: transforms.fromString.boolean.optional(),
  xss_header: transforms.fromString.boolean.optional(),
  frame_options: transforms.fromString.boolean.optional(),
  path_traversal: transforms.fromString.boolean.optional(),
  cookie_tossing: transforms.fromString.boolean.optional(),
  ip_spoofing: transforms.fromString.boolean.optional(),
  strict_transport: transforms.fromString.boolean.optional(),
});

const staticSiteSchema = z.object({
  host: z.string().optional(),
  ssl: transforms.fromString.boolean.optional(),
  secret: z.string().optional(),
  authentication: staticSiteAuthenticationSchema.optional(),
  authenticity: staticSiteAuthenticitySchema.optional(),
  middleware: staticSiteMiddlewareSchema.optional(),
});

const staticStorageDbConnectionSchema = z.object({
  url: z.string().optional(),
});

const staticStorageDbSchema = z.object({
  connection: staticStorageDbConnectionSchema.optional(),
  database_mapping: z.record(z.string(), transforms.fromString.number).optional(),
});

const staticStorageSchema = z.object({
  db: staticStorageDbSchema.optional(),
});

const staticMailConnectionSchema = z.object({
  mode: z.string().optional(),
  region: z.string().optional(),
  from: transforms.fromString.optionalEmail,
  fromname: z.string().optional(),
  host: z.string().optional(),
  port: transforms.fromString.number.optional(),
  user: nullableString,
  pass: nullableString,
  auth: z.string().optional(),
  // Can be true/false, 'true'/'false', or nil
  tls: transforms.fromString.boolean.nullable().optional(),
});

const staticMailValidationSchema = z.object({
  // Reuses the detailed validation schema
  default: individualMailValidationSchema.optional(),
});

const staticMailSchema = z.object({
  connection: staticMailConnectionSchema.optional(),
  validation: staticMailValidationSchema.optional(),
});

const staticLoggingSchema = z.object({
  http_requests: transforms.fromString.boolean.optional(),
});

const staticI18nSchema = z.object({
  enabled: transforms.fromString.boolean.optional(),
  default_locale: z.string().optional(),
  fallback_locale: z.record(z.string(), z.union([z.array(z.string()), z.string()])).optional(),
  locales: z.array(z.string()).optional(),
  incomplete: z.array(z.string()).optional(),
});

const staticDevelopmentSchema = z.object({
  enabled: transforms.fromString.boolean.optional(),
  debug: transforms.fromString.boolean.optional(),
  frontend_host: z.string().optional(),
});

const staticExperimentalSchema = z.object({
  allow_nil_global_secret: transforms.fromString.boolean.optional(),
  rotated_secrets: z.array(z.string()).optional(),
  freeze_app: transforms.fromString.boolean.optional(),
});

export const staticConfigSchema = z.object({
  site: staticSiteSchema.optional(),
  storage: staticStorageSchema.optional(),
  mail: staticMailSchema.optional(),
  logging: staticLoggingSchema.optional(),
  i18n: staticI18nSchema.optional(),
  development: staticDevelopmentSchema.optional(),
  experimental: staticExperimentalSchema.optional(),
});

export type StaticConfig = z.infer<typeof staticConfigSchema>;

// Rate limit types for better type safety
export type RateLimitKey = (typeof RATE_LIMIT_KEYS)[number] | string;
export type RateLimits = z.infer<typeof limitsSchema>;
export { RATE_LIMIT_KEYS };
