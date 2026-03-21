// src/types/declarations/bootstrap.d.ts
//
// TypeScript declarations for server-injected bootstrap state.
//
// UI-specific types (Footer, Header, Message, etc.) are derived from the Zod
// schema at @/schemas/bootstrap.schema.ts using z.infer<>.
//
// Shared entity types (Customer, BrandSettings, etc.) continue to use v2 shapes
// for compatibility with the rest of the codebase.

// Re-export UI types from the Zod schema (single source of truth)
export type {
  FooterLink,
  FooterGroup,
  FooterLinksConfig,
  HeaderLogo,
  HeaderBranding,
  HeaderNavigation,
  HeaderConfig,
  UiInterface,
  LocaleInfo,
  Message,
  DevelopmentConfig,
  SSOProvider,
  SSOConfig,
  Features,
  Organization,
} from '@/schemas/bootstrap.schema';

// Re-export validation utilities
export {
  bootstrapUiSchema,
  parseBootstrapUi,
  BOOTSTRAP_UI_DEFAULTS,
} from '@/schemas/bootstrap.schema';

// Import shared types from v2 shapes (these have complex transforms)
import {
  AuthenticationSettings,
  BrandSettings,
  Customer,
  RegionsConfig,
  SecretOptions,
} from '@/schemas/shapes/v2';
import type { Locale } from '@/schemas/i18n/locale';
import { Stripe } from 'stripe';
import { FallbackLocale } from 'vue-i18n';

import { DiagnosticsConfig } from '../diagnostics';

// Re-export for backward compatibility
export type {
  AuthenticationSettings,
  BrandSettings,
  Customer,
  RegionsConfig,
  SecretOptions,
};
export type { DiagnosticsConfig };

/**
 * BootstrapPayload is the canonical type for server-injected state.
 *
 * This interface uses:
 * - UI types from @/schemas/bootstrap.schema (FooterLinksConfig, UiInterface, etc.)
 * - Entity types from @/schemas/shapes/v2 (Customer, BrandSettings, etc.)
 * - Config types from @/types/diagnostics (DiagnosticsConfig)
 *
 * The corresponding Ruby backend code is in:
 * apps/web/core/views/serializers/
 */
export interface BootstrapPayload {
  apitoken?: string;

  /**
   * User is fully authenticated (all auth factors complete).
   * When true, user has full access to their account.
   */
  authenticated: boolean;

  /**
   * User is partially authenticated and awaiting MFA completion.
   * When true, user has passed first factor (email/password) but needs
   * to complete second factor (TOTP/WebAuthn) before full access.
   * The user menu will appear with an amber badge during this state.
   */
  awaiting_mfa: boolean;

  /**
   * Indicates whether the request had a valid session at the time of response.
   * This is crucial for error pages where authenticated=false but the user
   * had a valid session. The frontend uses this to preserve auth state and
   * avoid incorrect redirects to signin on server errors.
   */
  had_valid_session: boolean;

  /**
   * Whether the authenticated account has a password set.
   * SSO-only accounts (Entra, Google, GitHub) have no password.
   * Used to hide security settings (password change, MFA, recovery codes)
   * that are irrelevant for SSO-only users.
   */
  has_password?: boolean;

  baseuri: string;
  cust: Customer | null;
  custid: string;
  customer_since?: string;
  custom_domains?: string[];
  domains_enabled: boolean;
  email: string;
  frontend_host: string;

  i18n_enabled: boolean;
  locale: string;
  supported_locales: Locale[];
  fallback_locale: FallbackLocale;
  default_locale: Locale;

  /**
   * Date display format preference. Controls both date-only and date+time
   * display unless datetime_format is explicitly set.
   *
   * - 'locale': Browser-native locale formatting (default)
   * - 'iso8601', 'us', 'eu', 'eu-dot', 'uk', 'long': regional presets
   * - Any other string: a raw date-fns format pattern
   */
  date_format: string;

  /**
   * Optional override for date+time contexts. When set to 'locale' (the
   * default), datetime display falls back to the date_format setting.
   * Only set this when you need date-only and date+time to differ.
   *
   * Accepts the same values as date_format.
   */
  datetime_format: string;

  ot_version: string;
  ot_version_long: string;
  billing_enabled?: boolean;
  regions_enabled: boolean;
  ruby_version: string;

  /**
   * CSRF token for POST request validation.
   * Updated dynamically after POST requests.
   * Use useCsrfStore() to access current token.
   */
  shrimp: string;

  site_host: string;
  support_host: string;
  stripe_customer?: Stripe.Customer;
  stripe_subscriptions?: Stripe.Subscriptions[];
  authentication: AuthenticationSettings;
  secret_options: SecretOptions;

  regions: RegionsConfig;

  available_jurisdictions: string[];

  /**
   * Flag to disable pre-Vue color mode detection
   * after Vue app initialization
   */
  enjoyTheVue: boolean;

  /**
   * Homepage mode indicating accessibility state.
   * - 'protected': Homepage is accessible (bypass header present)
   * - null/undefined: No special mode, follow authentication.required
   */
  homepage_mode?: 'external' | 'internal' | null;

  /** Optional HTML banner displayed at page top */
  global_banner?: string;

  canonical_domain: string;
  domain_strategy: 'canonical' | 'subdomain' | 'custom' | 'invalid';
  domain_id: string;
  display_domain: string;
  domain_branding: BrandSettings;
  /** URL to custom domain logo image, or null if no logo uploaded */
  domain_logo: string | null;
  /** User's preferred domain context from session (server-side preference) */
  domain_context?: string | null;

  // UI types from schema
  messages: import('@/schemas/bootstrap.schema').Message[];

  d9s_enabled: boolean;
  diagnostics: DiagnosticsConfig;

  /** Development mode configuration */
  development?: import('@/schemas/bootstrap.schema').DevelopmentConfig;

  features: import('@/schemas/bootstrap.schema').Features;

  ui: import('@/schemas/bootstrap.schema').UiInterface;

  /**
   * Entitlement test mode (colonel only)
   * Allows testing with different plan entitlements temporarily.
   * entitlement_test_planid being set indicates test mode is active.
   */
  entitlement_test_planid?: string | null;
  entitlement_test_plan_name?: string | null;

  /**
   * Current user's organization (when authenticated)
   * Populated by OrganizationSerializer from OrganizationLoader context
   */
  organization?: import('@/schemas/bootstrap.schema').Organization;
}
