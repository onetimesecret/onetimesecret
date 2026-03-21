// src/tests/contracts/bootstrap-serializer-fields.ts
//
// Canonical field lists from Ruby backend serializers.
// Source: apps/web/core/views/serializers/*.rb
//
// Update this list when Ruby serializers change.
// The contract tests will fail if the TypeScript interface diverges from
// this list, preventing silent field stripping or mismatches.

// ============================================================================
// AUTHENTICATION SERIALIZER FIELDS
// Source: apps/web/core/views/serializers/authentication_serializer.rb
// ============================================================================
export const AUTHENTICATION_SERIALIZER_FIELDS = [
  'authenticated',
  'awaiting_mfa',
  'had_valid_session',
  'has_password',
  'custid',
  'cust',
  'email',
  'customer_since',
  'entitlement_test_planid',
  'entitlement_test_plan_name',
] as const;

// ============================================================================
// CONFIG SERIALIZER FIELDS
// Source: apps/web/core/views/serializers/config_serializer.rb
// ============================================================================
export const CONFIG_SERIALIZER_FIELDS = [
  'authentication',
  'd9s_enabled',
  'development',
  'diagnostics',
  'domains_enabled',
  'features',
  'frontend_host',
  'homepage_mode',
  'billing_enabled',
  'regions',
  'regions_enabled',
  'secret_options',
  'site_host',
  'support_host',
  'ui',
] as const;

// ============================================================================
// DOMAIN SERIALIZER FIELDS
// Source: apps/web/core/views/serializers/domain_serializer.rb
// ============================================================================
export const DOMAIN_SERIALIZER_FIELDS = [
  'canonical_domain',
  'custom_domains',
  'display_domain',
  'domain_branding',
  'domain_id',
  'domain_logo',
  'domain_context',
  'domain_strategy',
] as const;

// ============================================================================
// I18N SERIALIZER FIELDS
// Source: apps/web/core/views/serializers/i18n_serializer.rb
// ============================================================================
export const I18N_SERIALIZER_FIELDS = [
  'locale',
  'default_locale',
  'fallback_locale',
  'supported_locales',
  'i18n_enabled',
] as const;

// ============================================================================
// MESSAGES SERIALIZER FIELDS
// Source: apps/web/core/views/serializers/messages_serializer.rb
// ============================================================================
export const MESSAGES_SERIALIZER_FIELDS = ['messages', 'global_banner'] as const;

// ============================================================================
// ORGANIZATION SERIALIZER FIELDS
// Source: apps/web/core/views/serializers/organization_serializer.rb
// ============================================================================
export const ORGANIZATION_SERIALIZER_FIELDS = ['organization'] as const;

// ============================================================================
// SYSTEM SERIALIZER FIELDS
// Source: apps/web/core/views/serializers/system_serializer.rb
// ============================================================================
export const SYSTEM_SERIALIZER_FIELDS = [
  'ot_version',
  'ot_version_long',
  'ruby_version',
  'shrimp',
] as const;

// ============================================================================
// FIELDS ADDED BY initialize_view_vars (NOT via serializers)
// Source: apps/web/core/views/helpers/initialize_view_vars.rb
// These fields are part of view_vars but consumed directly by templates
// rather than being passed through serializers.
// ============================================================================
export const TEMPLATE_ONLY_FIELDS = [
  'baseuri', // Used in templates for og:url, sitemap, etc.
] as const;

// ============================================================================
// FIELDS ADDED ELSEWHERE (Frontend or template bootstrap)
// These are either frontend-only or injected via JavaScript in templates
// ============================================================================
export const NON_SERIALIZER_FIELDS = [
  'apitoken', // Optional field, only set in specific contexts
  'available_jurisdictions', // Derived from regions config
  'enjoyTheVue', // Set in JavaScript in template (index.rue)
  'stripe_customer', // Billing-specific, loaded separately
  'stripe_subscriptions', // Billing-specific, loaded separately
] as const;

// ============================================================================
// AGGREGATE COLLECTIONS
// ============================================================================

/**
 * All fields produced by Ruby serializers.
 * These fields should all have corresponding declarations in BootstrapPayload.
 */
export const ALL_SERIALIZER_FIELDS = [
  ...AUTHENTICATION_SERIALIZER_FIELDS,
  ...CONFIG_SERIALIZER_FIELDS,
  ...DOMAIN_SERIALIZER_FIELDS,
  ...I18N_SERIALIZER_FIELDS,
  ...MESSAGES_SERIALIZER_FIELDS,
  ...ORGANIZATION_SERIALIZER_FIELDS,
  ...SYSTEM_SERIALIZER_FIELDS,
] as const;

/**
 * All backend fields that appear in the bootstrap payload.
 * Includes serializer fields, template fields, and fields from other sources.
 */
export const ALL_BOOTSTRAP_FIELDS = [
  ...ALL_SERIALIZER_FIELDS,
  ...TEMPLATE_ONLY_FIELDS,
  ...NON_SERIALIZER_FIELDS,
] as const;

// Type exports for type-safe field access
export type AuthenticationSerializerField = (typeof AUTHENTICATION_SERIALIZER_FIELDS)[number];
export type ConfigSerializerField = (typeof CONFIG_SERIALIZER_FIELDS)[number];
export type DomainSerializerField = (typeof DOMAIN_SERIALIZER_FIELDS)[number];
export type I18nSerializerField = (typeof I18N_SERIALIZER_FIELDS)[number];
export type MessagesSerializerField = (typeof MESSAGES_SERIALIZER_FIELDS)[number];
export type OrganizationSerializerField = (typeof ORGANIZATION_SERIALIZER_FIELDS)[number];
export type SystemSerializerField = (typeof SYSTEM_SERIALIZER_FIELDS)[number];
export type BootstrapField = (typeof ALL_BOOTSTRAP_FIELDS)[number];
