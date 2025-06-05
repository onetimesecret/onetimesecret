// src/schemas/config/settings.ts

// import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Common flexible type validation for values that might be boolean or string representations
const booleanOrString = z.union([z.boolean(), z.string()]).optional();
// Common flexible type validation for values that might be number or string representations
const numberOrString = z.union([z.string(), z.number()]).optional();
const nullableString = z.string().nullable().optional();

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
  enabled: z.boolean().optional(), // Adjusted based on YAML <%= ... != 'false' %>
});

const userInterfaceHeaderSchema = z.object({
  enabled: z.boolean().optional(), // Adjusted
  branding: userInterfaceHeaderBrandingSchema.optional(),
  navigation: userInterfaceHeaderNavigationSchema.optional(),
});

const userInterfaceFooterLinkSchema = z.object({
  text: z.string().optional(),
  i18n_key: z.string().optional(),
  url: nullableString, // Can be nil from ENV
  external: z.boolean().optional(), // Adjusted
  icon: z.string().optional(), // Added
});

const userInterfaceFooterGroupSchema = z.object({
  name: z.string().optional(), // YAML :name:
  i18n_key: z.string().optional(),
  links: z.array(userInterfaceFooterLinkSchema).optional(),
});

const userInterfaceFooterLinksSchema = z.object({
  enabled: z.boolean().optional(), // Adjusted
  groups: z.array(userInterfaceFooterGroupSchema).optional(),
});

const userInterfaceSchema = z.object({
  enabled: z.boolean().optional(), // Adjusted
  header: userInterfaceHeaderSchema.optional(),
  footer_links: userInterfaceFooterLinksSchema.optional(),
  signup: z.boolean().optional(), // Added
  signin: z.boolean().optional(), // Added
  autoverify: z.null().optional(), // Added, YAML has 'null'
});

const apiSchema = z.object({
  enabled: z.boolean().optional(), // Adjusted
});

const secretOptionsSchema = z.object({
  default_ttl: numberOrString.nullable().optional(), // Can be nil from ENV
  ttl_options: z
    .union([z.string(), z.array(z.number())])
    .nullable()
    .optional(), // Can be nil from ENV
});

const featuresIncomingSchema = z.object({
  enabled: z.boolean().optional(),
  email: z.string().optional(),
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
  enabled: booleanOrString, // YAML: <%= ENV['REGIONS_ENABLED'] || true %>
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
  enabled: z.boolean().optional(), // YAML: <%= ENV['PLANS_ENABLED'] == 'true' || false %>
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
  enabled: booleanOrString, // YAML: <%= ENV['DOMAINS_ENABLED'] || true %>
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
  sampleRate: numberOrString,
  maxBreadcrumbs: numberOrString,
  logErrors: booleanOrString,
});

const diagnosticsSentryBackendSchema = z.object({
  dsn: nullableString,
});

const diagnosticsSentryFrontendSchema = z.object({
  dsn: nullableString,
  trackComponents: booleanOrString,
});

const diagnosticsSentrySchema = z.object({
  defaults: diagnosticsSentryDefaultsSchema.optional(),
  backend: diagnosticsSentryBackendSchema.optional(),
  frontend: diagnosticsSentryFrontendSchema.optional(),
});

const diagnosticsSchema = z.object({
  enabled: z.boolean().optional(), // YAML: <%= ENV['DIAGNOSTICS_ENABLED'] == 'true' || false %>
  sentry: diagnosticsSentrySchema.optional(),
});

const limitsSchema = z.object({
  check_status: z.number().optional(),
  create_secret: z.number().optional(),
  create_account: z.number().optional(),
  update_account: z.number().optional(),
  email_recipient: z.number().optional(),
  send_feedback: z.number().optional(),
  authenticate_session: z.number().optional(),
  dashboard: z.number().optional(),
  failed_passphrase: z.number().optional(),
  show_metadata: z.number().optional(),
  show_secret: z.number().optional(),
  burn_secret: z.number().optional(),
  destroy_account: z.number().optional(),
  forgot_password_request: z.number().optional(),
  forgot_password_reset: z.number().optional(),
  add_domain: z.number().optional(),
  remove_domain: z.number().optional(),
  list_domains: z.number().optional(),
  get_domain: z.number().optional(),
  verify_domain: z.number().optional(),
  get_page: z.number().optional(),
  report_exception: z.number().optional(),
  attempt_secret_access: z.number().optional(),
  generate_apitoken: z.number().optional(),
  update_branding: z.number().optional(),
  destroy_session: z.number().optional(),
  get_domain_brand: z.number().optional(),
  get_domain_logo: z.number().optional(),
  get_image: z.number().optional(),
  remove_domain_logo: z.number().optional(),
  show_account: z.number().optional(),
  stripe_webhook: z.number().optional(),
  update_domain_brand: z.number().optional(),
  view_colonel: z.number().optional(),
  external_redirect: z.number().optional(),
  update_system_settings: z.number().optional(),
});

const individualMailValidationSchema = z.object({
  default_validation_type: z.string().optional(),
  verifier_email: z.string().optional(),
  verifier_domain: z.string().optional(),
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
      tracking_event: z.string().optional(), // YAML :all
      stdout: z.boolean().optional(),
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
  enabled: z.boolean().optional(),
  colonels: z.array(z.string()).optional(),
});

const staticSiteAuthenticitySchema = z.object({
  type: z.string().optional(),
  secret_key: z.string().optional(),
});

const staticSiteMiddlewareSchema = z.object({
  static_files: z.boolean().optional(),
  utf8_sanitizer: z.boolean().optional(),
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
  host: z.string().optional(),
  ssl: z.boolean().optional(),
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
  database_mapping: z.record(z.string(), z.number()).optional(),
});

const staticStorageSchema = z.object({
  db: staticStorageDbSchema.optional(),
});

const staticMailConnectionSchema = z.object({
  mode: z.string().optional(),
  region: z.string().optional(),
  from: z.string().optional(),
  fromname: z.string().optional(),
  host: z.string().optional(),
  port: numberOrString,
  user: nullableString,
  pass: nullableString,
  auth: z.string().optional(),
  tls: booleanOrString.nullable().optional(), // Can be true/false, 'true'/'false', or nil
});

const staticMailValidationSchema = z.object({
  default: individualMailValidationSchema.optional(), // Reuses the detailed validation schema
});

const staticMailSchema = z.object({
  connection: staticMailConnectionSchema.optional(),
  validation: staticMailValidationSchema.optional(),
});

const staticLoggingSchema = z.object({
  http_requests: z.boolean().optional(),
});

const staticI18nSchema = z.object({
  enabled: booleanOrString,
  default_locale: z.string().optional(),
  fallback_locale: z.record(z.string(), z.union([z.array(z.string()), z.string()])).optional(),
  locales: z.array(z.string()).optional(),
  incomplete: z.array(z.string()).optional(),
});

const staticDevelopmentSchema = z.object({
  enabled: z.boolean().optional(),
  debug: z.boolean().optional(),
  frontend_host: z.string().optional(),
});

const staticExperimentalSchema = z.object({
  allow_nil_global_secret: z.boolean().optional(),
  rotated_secrets: z.array(z.string()).optional(),
  freeze_app: z.boolean().optional(),
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
